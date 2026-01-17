"""
Kafka Streams CDC Processor
Real-time CDC event routing and lightweight transformations
"""

import json
import os
import sys
from typing import Dict, Any, Optional
from dataclasses import dataclass
from datetime import datetime

from pyspark.sql import SparkSession
from pyspark import SparkConf
from pyspark.streaming.kafka import KafkaUtils
from pyspark.streaming import StreamingContext
from pyspark.sql.functions import *
from pyspark.sql.types import *
import json


class CDCStreamProcessor:
    """Kafka Streams application for CDC event processing"""
    
    def __init__(self, bootstrap_servers: str):
        self.bootstrap_servers = bootstrap_servers
        self.spark = self._create_spark_session()
        
    def _create_spark_session(self) -> SparkSession:
        """Initialize Spark session with Kafka and Iceberg support"""
        spark = SparkSession.builder \
            .appName("CDC-Stream-Processor") \
            .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
            .config("spark.sql.catalog.spark_catalog", "org.apache.iceberg.spark.SparkCatalog") \
            .config("spark.sql.catalog.spark_catalog.type", "hive") \
            .config("spark.sql.adaptive.enabled", "true") \
            .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
            .config("spark.sql.shuffle.partitions", "10") \
            .config("spark.default.parallelism", "10") \
            .getOrCreate()
        
        spark.sparkContext.setLogLevel("WARN")
        return spark
    
    def create_cdc_stream(self, topics: list, checkpoint_dir: str):
        """Create CDC stream from Kafka"""
        
        # Create streaming DataFrame
        raw_stream = self.spark.readStream \
            .format("kafka") \
            .option("kafka.bootstrap.servers", self.bootstrap_servers) \
            .option("subscribe", ",".join(topics)) \
            .option("startingOffsets", "latest") \
            .option("failOnDataLoss", "false") \
            .load()
        
        return raw_stream
    
    def process_cdc_events(self, stream_df):
        """Process CDC events with routing logic"""
        
        # Parse CDC payload
        parsed_df = stream_df.select(
            col("topic"),
            col("partition"),
            col("offset"),
            col("timestamp"),
            from_json(
                col("value").cast("string"),
                self._get_cdc_schema()
            ).alias("cdc_payload")
        )
        
        # Extract CDC operation details
        processed_df = parsed_df.select(
            col("topic"),
            col("partition"),
            col("offset"),
            col("timestamp"),
            col("cdc_payload.op").alias("operation"),
            col("cdc_payload.before").alias("before_state"),
            col("cdc_payload.after").alias("after_state"),
            col("cdc_payload.ts_ms").alias("source_timestamp"),
            col("cdc_payload.source.db").alias("source_database"),
            col("cdc_payload.source.table").alias("source_table"),
            current_timestamp().alias("processed_at")
        )
        
        # Add routing metadata
        processed_df = processed_df \
            .withColumn("routing_key", 
                concat(col("source_table"), lit("_"), col("operation"))
            ) \
            .withColumn("is_delete", col("operation") == lit("d"))
        
        return processed_df
    
    def _get_cdc_schema(self) -> StructType:
        """Define CDC event schema"""
        return StructType([
            StructField("before", StructType([
                StructField("id", LongType(), True),
                StructField("_change_type", StringType(), True)
            ]), True),
            StructField("after", StructType([
                StructField("id", LongType(), True)
            ]), True),
            StructField("op", StringType(), True),
            StructField("ts_ms", LongType(), True),
            StructField("source", StructType([
                StructField("db", StringType(), True),
                StructField("table", StringType(), True)
            ]), True)
        ])
    
    def route_to_topics(self, processed_df, output_topics: Dict[str, str]):
        """Route processed events to appropriate topics"""
        
        # Define routing logic
        for topic, condition in output_topics.items():
            query = processed_df \
                .filter(expr(condition)) \
                .select(
                    to_json(struct("*")).alias("value"),
                    col("topic").alias("key")
                ) \
                .writeStream \
                .format("kafka") \
                .option("kafka.bootstrap.servers", self.bootstrap_servers) \
                .option("topic", topic) \
                .option("checkpointLocation", f"/tmp/kafka-streams/checkpoints/{topic}") \
                .outputMode("append") \
                .start()
            
            print(f"Started routing to topic: {topic}")
    
    def enrich_with_reference_data(self, cdc_df, reference_tables: Dict[str, str]):
        """Enrich CDC events with reference data"""
        
        for table_name, s3_path in reference_tables.items():
            # Read reference data from S3/Iceberg
            ref_df = self.spark.read.format("iceberg").load(s3_path)
            
            # Cache for reuse
            ref_df.cache()
            
            # Enrich based on table type
            if table_name == "users":
                cdc_df = cdc_df.join(
                    ref_df.select("id", "name", "email"),
                    cdc_df.after_state["id"] == ref_df.id,
                    "left"
                )
            elif table_name == "products":
                cdc_df = cdc_df.join(
                    ref_df.select("id", "name", "category", "price"),
                    cdc_df.after_state["id"] == ref_df.id,
                    "left"
                )
        
        return cdc_df
    
    def detect_data_quality_issues(self, cdc_df):
        """Detect potential data quality issues in real-time"""
        
        quality_df = cdc_df.withColumn(
            "quality_score",
            expr("""
                CASE 
                    WHEN operation IN ('c', 'u', 'd') THEN 1.0
                    ELSE 0.0
                END
            """)
        )
        
        # Alert on delete operations
        alerts = quality_df.filter(col("is_delete") == True) \
            .select(
                col("source_table"),
                col("operation"),
                col("before_state").alias("deleted_record"),
                col("timestamp")
            )
        
        return alerts


class LocalCDCStreamProcessor(CDCStreamProcessor):
    """Extended processor for local development with Docker"""
    
    def __init__(self):
        # Local Kafka bootstrap servers
        bootstrap_servers = os.getenv(
            "KAFKA_BOOTSTRAP_SERVERS", 
            "localhost:9092"
        )
        super().__init__(bootstrap_servers)
    
    def create_test_data_stream(self):
        """Create a test stream for development"""
        
        # Create test data generator
        test_data = [
            {"op": "c", "after": {"id": 1, "name": "John Doe", "email": "john@example.com"}},
            {"op": "c", "after": {"id": 2, "name": "Jane Smith", "email": "jane@example.com"}},
            {"op": "u", "before": {"id": 1}, "after": {"id": 1, "name": "John Updated"}},
            {"op": "d", "before": {"id": 2}}
        ]
        
        return self.spark.sparkContext.parallelize(test_data)


def run_stream_processor():
    """Main entry point for Kafka Streams CDC Processor"""
    
    bootstrap_servers = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
    topics = os.getenv("CDC_TOPICS", "cdc.users,cdc.products,cdc.orders").split(",")
    
    print(f"Starting CDC Stream Processor...")
    print(f"Bootstrap Servers: {bootstrap_servers}")
    print(f"Subscribed Topics: {topics}")
    
    # Initialize processor
    processor = CDCStreamProcessor(bootstrap_servers)
    
    # Create stream
    stream_df = processor.create_cdc_stream(topics, "/tmp/checkpoints")
    
    # Process events
    processed_df = processor.process_cdc_events(stream_df)
    
    # Define routing rules
    routing_rules = {
        "processed.users": "source_table = 'users'",
        "processed.products": "source_table = 'products'",
        "processed.orders": "source_table = 'orders'"
    }
    
    # Route to topics
    processor.route_to_topics(processed_df, routing_rules)
    
    # Start query
    print("CDC Stream Processor started successfully!")
    print("Press Ctrl+C to stop...")
    
    # Wait for termination
    import time
    try:
        while True:
            time.sleep(10)
    except KeyboardInterrupt:
        print("\nStopping CDC Stream Processor...")
        processor.spark.stop()


if __name__ == "__main__":
    run_stream_processor()

