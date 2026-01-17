import sys
import logging
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import DataFrame
from pyspark.sql.functions import *
from pyspark.sql.types import *
from pyspark.sql.window import Window

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Glue context
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'S3_BUCKET'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Configuration
DATABASE_NAME = args['DATABASE_NAME']
S3_BUCKET = args['S3_BUCKET']

logger.info(f"Starting Gold Processor Job")
logger.info(f"Database: {DATABASE_NAME}")
logger.info(f"S3 Bucket: {S3_BUCKET}")

# Configure Iceberg catalog
spark.conf.set("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.warehouse", f"s3://{S3_BUCKET}/iceberg-warehouse/")
spark.conf.set("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")

def check_table_exists(table_name: str) -> bool:
    """Check if Iceberg table exists"""
    try:
        result = spark.sql(f"SELECT * FROM glue_catalog.{DATABASE_NAME}_{table_name} LIMIT 1")
        result.collect()
        return True
    except Exception as e:
        logger.warning(f"Table {table_name} does not exist or is empty: {str(e)}")
        return False

def create_iceberg_table_if_not_exists(table_name: str, schema, path: str):
    """Create Iceberg table if it doesn't exist"""
    table_identifier = f"glue_catalog.{DATABASE_NAME}_{table_name}"
    logger.info(f"Creating table {table_identifier} if not exists...")
    
    try:
        spark.sql(f"""
            CREATE TABLE IF NOT EXISTS {table_identifier} (
                {', '.join([f'{field.name} {field.dataType.simpleString()}' for field in schema.fields])}
            ) USING iceberg
            PARTITIONED BY (year(created_at))
            LOCATION '{path}'
            TBLPROPERTIES ('format-version'='2')
        """)
        logger.info(f"Table {table_identifier} created/verified successfully")
    except Exception as e:
        logger.warning(f"Table creation warning: {str(e)}")

def create_user_analytics():
    """Create analytics-ready user data"""
    logger.info("Creating user analytics...")
    
    # Read from Silver layer
    try:
        users_silver = spark.read.format("iceberg").load(f"s3://{S3_BUCKET}/silver/users/")
        orders_silver = spark.read.format("iceberg").load(f"s3://{S3_BUCKET}/silver/orders/")
    except Exception as e:
        logger.warning(f"Could not read Silver layer tables: {str(e)}")
        return None
    
    # Get latest user records (handle CDC)
    window_spec = Window.partitionBy("id").orderBy(desc("processed_at"))
    try:
        latest_users = users_silver.withColumn("row_num", row_number().over(window_spec)) \
                                  .filter(col("row_num") == 1) \
                                  .filter(col("is_active") == True) \
                                  .drop("row_num")
        
        # Calculate user metrics
        user_metrics = orders_silver.filter(col("is_active") == True) \
                                   .groupBy("user_id") \
                                   .agg(
                                       count("*").alias("total_orders"),
                                       sum("total_amount").alias("total_spent"),
                                       avg("total_amount").alias("avg_order_value"),
                                       max("created_at").alias("last_order_date"),
                                       min("created_at").alias("first_order_date")
                                   )
        
        # Join users with metrics
        user_analytics = latest_users.alias("u") \
                                    .join(user_metrics.alias("m"), col("u.id") == col("m.user_id"), "left") \
                                    .select(
                                        col("u.id").alias("user_id"),
                                        col("u.name").alias("full_name"),
                                        col("u.email_domain"),
                                        col("u.created_at").alias("registration_date"),
                                        col("u.updated_at").alias("last_activity"),
                                        coalesce(col("m.total_orders"), lit(0)).alias("total_orders"),
                                        coalesce(col("m.total_spent"), lit(0.0)).alias("total_spent"),
                                        coalesce(col("m.avg_order_value"), lit(0.0)).alias("avg_order_value"),
                                        col("m.last_order_date"),
                                        col("m.first_order_date")
                                    )
        
        # Add user segmentation
        user_analytics = user_analytics.withColumn(
            "user_segment",
            when(col("total_spent") >= 1000, "VIP")
            .when(col("total_spent") >= 500, "Premium")
            .when(col("total_spent") >= 100, "Regular")
            .when(col("total_orders") > 0, "Active")
            .otherwise("New")
        )
        
        # Add recency analysis
        user_analytics = user_analytics.withColumn(
            "days_since_last_order",
            when(col("last_order_date").isNotNull(),
                 datediff(current_date(), col("last_order_date")))
            .otherwise(lit(None))
        )
        
        # Add customer lifetime value category
        user_analytics = user_analytics.withColumn(
            "clv_category",
            when(col("total_spent") >= 2000, "High")
            .when(col("total_spent") >= 500, "Medium")
            .otherwise("Low")
        )
        
        return user_analytics
    except Exception as e:
        logger.error(f"Error creating user analytics: {str(e)}")
        return None

def create_product_analytics():
    """Create analytics-ready product data"""
    logger.info("Creating product analytics...")
    
    # Read from Silver layer
    try:
        products_silver = spark.read.format("iceberg").load(f"s3://{S3_BUCKET}/silver/products/")
        orders_silver = spark.read.format("iceberg").load(f"s3://{S3_BUCKET}/silver/orders/")
    except Exception as e:
        logger.warning(f"Could not read Silver layer tables: {str(e)}")
        return None
    
    try:
        # Get latest product records
        window_spec = Window.partitionBy("id").orderBy(desc("processed_at"))
        latest_products = products_silver.withColumn("row_num", row_number().over(window_spec)) \
                                       .filter(col("row_num") == 1) \
                                       .filter(col("is_active") == True) \
                                       .drop("row_num")
        
        # Calculate product metrics
        product_metrics = orders_silver.filter(col("is_active") == True) \
                                      .groupBy("product_id") \
                                      .agg(
                                          count("*").alias("total_orders"),
                                          sum("quantity").alias("total_quantity_sold"),
                                          sum("total_amount").alias("total_revenue"),
                                          avg("quantity").alias("avg_quantity_per_order"),
                                          countDistinct("user_id").alias("unique_customers")
                                      )
        
        # Join products with metrics
        product_analytics = latest_products.alias("p") \
                                         .join(product_metrics.alias("m"), col("p.id") == col("m.product_id"), "left") \
                                         .select(
                                             col("p.id").alias("product_id"),
                                             col("p.name").alias("product_name"),
                                             col("p.category"),
                                             col("p.price"),
                                             col("p.price_category"),
                                             coalesce(col("m.total_orders"), lit(0)).alias("total_orders"),
                                             coalesce(col("m.total_quantity_sold"), lit(0)).alias("total_quantity_sold"),
                                             coalesce(col("m.total_revenue"), lit(0.0)).alias("total_revenue"),
                                             coalesce(col("m.avg_quantity_per_order"), lit(0.0)).alias("avg_quantity_per_order"),
                                             coalesce(col("m.unique_customers"), lit(0)).alias("unique_customers")
                                         )
        
        # Add performance metrics
        product_analytics = product_analytics.withColumn(
            "revenue_per_order",
            when(col("total_orders") > 0, col("total_revenue") / col("total_orders"))
            .otherwise(lit(0.0))
        )
        
        # Add popularity ranking
        window_popularity = Window.orderBy(desc("total_orders"))
        product_analytics = product_analytics.withColumn(
            "popularity_rank",
            row_number().over(window_popularity)
        )
        
        # Add revenue ranking
        window_revenue = Window.orderBy(desc("total_revenue"))
        product_analytics = product_analytics.withColumn(
            "revenue_rank",
            row_number().over(window_revenue)
        )
        
        # Add performance category
        product_analytics = product_analytics.withColumn(
            "performance_category",
            when(col("popularity_rank") <= 10, "Top Seller")
            .when(col("revenue_rank") <= 10, "High Revenue")
            .when(col("total_orders") > 5, "Popular")
            .when(col("total_orders") > 0, "Active")
            .otherwise("New")
        )
        
        return product_analytics
    except Exception as e:
        logger.error(f"Error creating product analytics: {str(e)}")
        return None

def create_sales_analytics():
    """Create sales analytics and trends"""
    logger.info("Creating sales analytics...")
    
    # Read from Silver layer
    try:
        orders_silver = spark.read.format("iceberg").load(f"s3://{S3_BUCKET}/silver/orders/")
        users_silver = spark.read.format("iceberg").load(f"s3://{S3_BUCKET}/silver/users/")
        products_silver = spark.read.format("iceberg").load(f"s3://{S3_BUCKET}/silver/products/")
    except Exception as e:
        logger.warning(f"Could not read Silver layer tables: {str(e)}")
        return None, None
    
    try:
        # Filter active records
        active_orders = orders_silver.filter(col("is_active") == True)
        
        # Daily sales summary
        daily_sales = active_orders.withColumn("order_date", to_date(col("created_at"))) \
                                  .groupBy("order_date") \
                                  .agg(
                                      count("*").alias("daily_orders"),
                                      sum("total_amount").alias("daily_revenue"),
                                      avg("total_amount").alias("avg_order_value"),
                                      countDistinct("user_id").alias("unique_customers")
                                  ) \
                                  .withColumn("day_of_week", dayofweek(col("order_date"))) \
                                  .withColumn("month", month(col("order_date"))) \
                                  .withColumn("year", year(col("order_date")))
        
        # Add moving averages
        window_7d = Window.orderBy("order_date").rowsBetween(-6, 0)
        window_30d = Window.orderBy("order_date").rowsBetween(-29, 0)
        
        daily_sales = daily_sales.withColumn(
            "revenue_7d_avg",
            avg("daily_revenue").over(window_7d)
        ).withColumn(
            "revenue_30d_avg",
            avg("daily_revenue").over(window_30d)
        )
        
        # Category performance
        category_performance = active_orders.alias("o") \
                                           .join(products_silver.alias("p"), col("o.product_id") == col("p.id")) \
                                           .groupBy("p.category") \
                                           .agg(
                                               count("*").alias("total_orders"),
                                               sum("o.total_amount").alias("total_revenue"),
                                               avg("o.total_amount").alias("avg_order_value"),
                                               countDistinct("o.user_id").alias("unique_customers")
                                           )
        
        return daily_sales, category_performance
    except Exception as e:
        logger.error(f"Error creating sales analytics: {str(e)}")
        return None, None

def main():
    """Main processing function"""
    logger.info("Starting Gold layer processing...")
    
    # Check if Silver layer tables exist
    silver_tables_exist = all([
        check_table_exists("silver_users"),
        check_table_exists("silver_products"),
        check_table_exists("silver_orders")
    ])
    
    if not silver_tables_exist:
        logger.warning("Silver layer tables not found. Please run CDC Processor first to create Bronze/Silver tables.")
        logger.info("Gold layer processing skipped (no data in Silver layer)")
        return
    
    # Create analytics datasets
    user_analytics = create_user_analytics()
    product_analytics = create_product_analytics()
    daily_sales, category_performance = create_sales_analytics()
    
    # Write to Gold layer
    if user_analytics is not None:
        logger.info("Writing user analytics to Gold layer...")
        user_analytics.write \
                      .format("iceberg") \
                      .mode("overwrite") \
                      .option("path", f"s3://{S3_BUCKET}/gold/user_analytics/") \
                      .save()
        logger.info("User analytics written successfully")
    else:
        logger.warning("Skipping user analytics - no data")
    
    if product_analytics is not None:
        logger.info("Writing product analytics to Gold layer...")
        product_analytics.write \
                         .format("iceberg") \
                         .mode("overwrite") \
                         .option("path", f"s3://{S3_BUCKET}/gold/product_analytics/") \
                         .save()
        logger.info("Product analytics written successfully")
    else:
        logger.warning("Skipping product analytics - no data")
    
    if daily_sales is not None and category_performance is not None:
        logger.info("Writing daily sales to Gold layer...")
        daily_sales.write \
                   .format("iceberg") \
                   .mode("overwrite") \
                   .option("path", f"s3://{S3_BUCKET}/gold/daily_sales/") \
                   .save()
        
        logger.info("Writing category performance to Gold layer...")
        category_performance.write \
                            .format("iceberg") \
                            .mode("overwrite") \
                            .option("path", f"s3://{S3_BUCKET}/gold/category_performance/") \
                            .save()
        logger.info("Sales analytics written successfully")
    else:
        logger.warning("Skipping sales analytics - no data")
    
    # Show sample data if available
    if user_analytics is not None:
        print("Sample User Analytics:")
        user_analytics.show(10, truncate=False)
    
    if product_analytics is not None:
        print("Sample Product Analytics:")
        product_analytics.show(10, truncate=False)
    
    if daily_sales is not None:
        print("Sample Daily Sales:")
        daily_sales.show(10, truncate=False)
    
    logger.info("Gold layer processing completed successfully!")

if __name__ == "__main__":
    main()

job.commit()

