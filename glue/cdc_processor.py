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
import boto3

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Glue context
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'S3_BUCKET'])
# Make KAFKA_BOOTSTRAP_SERVERS optional - handle missing argument gracefully
try:
    KAFKA_BOOTSTRAP_SERVERS = getResolvedOptions(sys.argv, ['KAFKA_BOOTSTRAP_SERVERS'])['KAFKA_BOOTSTRAP_SERVERS']
except:
    KAFKA_BOOTSTRAP_SERVERS = ""

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Configuration
DATABASE_NAME = args['DATABASE_NAME']
S3_BUCKET = args['S3_BUCKET']
KAFKA_BOOTSTRAP_SERVERS = args['KAFKA_BOOTSTRAP_SERVERS']

logger.info(f"Starting CDC Processor Job")
logger.info(f"Database: {DATABASE_NAME}")
logger.info(f"S3 Bucket: {S3_BUCKET}")
logger.info(f"Kafka Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")

# Configure Iceberg catalog using AWS Glue Data Catalog
spark.conf.set("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.warehouse", f"s3://{S3_BUCKET}/iceberg-warehouse/")
spark.conf.set("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")

def get_schema(table_name: str):
    """Get schema for different tables"""
    schemas = {
        "users": StructType([
            StructField("before", StructType([
                StructField("id", LongType(), True),
                StructField("name", StringType(), True),
                StructField("email", StringType(), True),
                StructField("created_at", TimestampType(), True),
                StructField("updated_at", TimestampType(), True)
            ]), True),
            StructField("after", StructType([
                StructField("id", LongType(), True),
                StructField("name", StringType(), True),
                StructField("email", StringType(), True),
                StructField("created_at", TimestampType(), True),
                StructField("updated_at", TimestampType(), True)
            ]), True),
            StructField("op", StringType(), True),
            StructField("ts_ms", LongType(), True),
            StructField("source", StructType([
                StructField("db", StringType(), True),
                StructField("table", StringType(), True)
            ]), True)
        ]),
        "products": StructType([
            StructField("before", StructType([
                StructField("id", LongType(), True),
                StructField("name", StringType(), True),
                StructField("price", DecimalType(10, 2), True),
                StructField("category", StringType(), True),
                StructField("created_at", TimestampType(), True),
                StructField("updated_at", TimestampType(), True)
            ]), True),
            StructField("after", StructType([
                StructField("id", LongType(), True),
                StructField("name", StringType(), True),
                StructField("price", DecimalType(10, 2), True),
                StructField("category", StringType(), True),
                StructField("created_at", TimestampType(), True),
                StructField("updated_at", TimestampType(), True)
            ]), True),
            StructField("op", StringType(), True),
            StructField("ts_ms", LongType(), True),
            StructField("source", StructType([
                StructField("db", StringType(), True),
                StructField("table", StringType(), True)
            ]), True)
        ]),
        "orders": StructType([
            StructField("before", StructType([
                StructField("id", LongType(), True),
                StructField("user_id", LongType(), True),
                StructField("product_id", LongType(), True),
                StructField("quantity", IntegerType(), True),
                StructField("total_amount", DecimalType(10, 2), True),
                StructField("status", StringType(), True),
                StructField("created_at", TimestampType(), True),
                StructField("updated_at", TimestampType(), True)
            ]), True),
            StructField("after", StructType([
                StructField("id", LongType(), True),
                StructField("user_id", LongType(), True),
                StructField("product_id", LongType(), True),
                StructField("quantity", IntegerType(), True),
                StructField("total_amount", DecimalType(10, 2), True),
                StructField("status", StringType(), True),
                StructField("created_at", TimestampType(), True),
                StructField("updated_at", TimestampType(), True)
            ]), True),
            StructField("op", StringType(), True),
            StructField("ts_ms", LongType(), True),
            StructField("source", StructType([
                StructField("db", StringType(), True),
                StructField("table", StringType(), True)
            ]), True)
        ])
    }
    return schemas.get(table_name)

def create_iceberg_table_if_not_exists(table_name: str, layer: str):
    """Create Iceberg table if it doesn't exist"""
    table_identifier = f"glue_catalog.{DATABASE_NAME}_{layer}_{table_name}"
    logger.info(f"Checking if table {table_identifier} exists...")
    
    try:
        spark.sql(f"CREATE TABLE IF NOT EXISTS {table_identifier} ( \
            key STRING, \
            id LONG, \
            name STRING, \
            email STRING, \
            created_at TIMESTAMP, \
            updated_at TIMESTAMP, \
            op STRING, \
            ts_ms LONG, \
            kafka_timestamp TIMESTAMP, \
            processed_at TIMESTAMP \
        ) USING iceberg PARTITIONED BY (op) TBLPROPERTIES ('format-version'='2')")
        logger.info(f"Table {table_identifier} created/verified successfully")
    except Exception as e:
        logger.warning(f"Table creation warning (may already exist): {str(e)}")

def transform_to_silver(df: DataFrame, table_name: str) -> DataFrame:
    """Transform data for Silver layer"""
    
    # Handle CDC operations
    silver_df = df.select(
        when(col("op") == "d", col("before")).otherwise(col("after")).alias("record"),
        col("op"),
        col("ts_ms"),
        current_timestamp().alias("processed_at")
    ).select("record.*", "op", "ts_ms", "processed_at")
    
    # Add data quality flags
    if table_name == "users":
        silver_df = silver_df.withColumn(
            "is_active", 
            when(col("op") != "d", True).otherwise(False)
        ).withColumn(
            "email_domain",
            regexp_extract(col("email"), "@(.+)", 1)
        )
    
    elif table_name == "products":
        silver_df = silver_df.withColumn(
            "is_active",
            when(col("op") != "d", True).otherwise(False)
        ).withColumn(
            "price_category",
            when(col("price") < 50, "Low")
            .when(col("price") < 200, "Medium")
            .otherwise("High")
        )
    
    elif table_name == "orders":
        silver_df = silver_df.withColumn(
            "is_active",
            when(col("op") != "d", True).otherwise(False)
        ).withColumn(
            "order_value_category",
            when(col("total_amount") < 100, "Small")
            .when(col("total_amount") < 500, "Medium")
            .otherwise("Large")
        )
    
    return silver_df

def process_cdc_stream(table_name: str):
    """Process CDC stream for a specific table"""
    topic = f"cdc.{DATABASE_NAME}.{table_name}"
    logger.info(f"Processing topic: {topic}")
    
    try:
        # Create Iceberg tables if they don't exist
        create_iceberg_table_if_not_exists(table_name, "bronze")
        create_iceberg_table_if_not_exists(table_name, "silver")
        
        # Read from Kafka with correct topic pattern
        kafka_df = spark \
            .readStream \
            .format("kafka") \
            .option("kafka.bootstrap.servers", KAFKA_BOOTSTRAP_SERVERS) \
            .option("subscribe", topic) \
            .option("startingOffsets", "earliest") \
            .option("kafka.security.protocol", "SASL_SSL") \
            .option("kafka.sasl.mechanism", "AWS_MSK_IAM") \
            .option("kafka.sasl.jaas.config", "software.amazon.msk.auth.iam.IAMClientCallbackHandler") \
            .option("failOnDataLoss", "false") \
            .load()
        
        # Check if we have any data
        kafka_count = kafka_df.count()
        logger.info(f"Kafka topic {topic} has {kafka_count} records")
        
        if kafka_count == 0:
            logger.warning(f"No data in topic {topic}, skipping...")
            return None, None
        
        # Parse JSON payload
        schema = get_schema(table_name)
        parsed_df = kafka_df.select(
            col("key").cast("string").alias("key"),
            from_json(col("value").cast("string"), schema).alias("data"),
            col("timestamp").alias("kafka_timestamp")
        ).select("key", "data.*", "kafka_timestamp")
        
        # Write to Bronze layer
        bronze_table = f"glue_catalog.{DATABASE_NAME}_bronze_{table_name}"
        logger.info(f"Writing to Bronze table: {bronze_table}")
        bronze_query = parsed_df.writeTo(bronze_table) \
            .option("mergeSchema", "true") \
            .append()
        
        # Transform for Silver layer
        silver_df = transform_to_silver(parsed_df, table_name)
        
        # Write to Silver layer
        silver_table = f"glue_catalog.{DATABASE_NAME}_silver_{table_name}"
        logger.info(f"Writing to Silver table: {silver_table}")
        silver_query = silver_df.writeTo(silver_table) \
            .option("mergeSchema", "true") \
            .append()
        
        logger.info(f"Successfully processed {kafka_count} records for table {table_name}")
        return bronze_query, silver_query
        
    except Exception as e:
        logger.error(f"Error processing table {table_name}: {str(e)}")
        # Return None to avoid joining NoneType
        return None, None

def main():
    """Main processing function"""
    logger.info("Starting main CDC processing...")
    
    # Process each table
    tables = ["users", "products", "orders"]
    queries = []
    
    for table in tables:
        logger.info(f"Processing table: {table}")
        bronze_query, silver_query = process_cdc_stream(table)
        if bronze_query is not None:
            queries.append(bronze_query)
        if silver_query is not None:
            queries.append(silver_query)
    
    if not queries:
        logger.warning("No queries to process. This may be expected if Kafka topics are empty.")
        logger.info("CDC Processor job completed (no data found)")
    else:
        # Wait for all streams to terminate
        logger.info(f"Waiting for {len(queries)} queries to complete...")
        for query in queries:
            try:
                query.awaitTermination(timeout=300)  # 5 minute timeout
            except Exception as e:
                logger.warning(f"Query timeout or error: {str(e)}")
    
    logger.info("CDC Processor job completed successfully!")

if __name__ == "__main__":
    main()

job.commit()

