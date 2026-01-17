# Real-Time CDC Data Engineering Platform

A complete, production-grade **Change Data Capture (CDC)** data platform that captures every database change (INSERT, UPDATE, DELETE) from PostgreSQL and processes them in real-time through a modern lakehouse architecture on AWS.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          POSTGRESQL (Source)                             │
│                    Captures every data change via                        │
│                   logical replication (wal_level=logical)               │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        DEBEZIUM (ECS Fargate)                            │
│                   • Captures CDC events in real-time                     │
│                   • Converts to Kafka topics                             │
│                   • Handles schema evolution                             │
│                   • Exactly-once delivery guarantee                      │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     APACHE KAFKA (MSK Cluster)                           │
│                   • Topics: cdc.users, cdc.products, cdc.orders         │
│                   • KRaft mode for high availability                     │
│                   • TLS encryption enabled                               │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       KAFKA STREAMS                                      │
│                   • Real-time routing                                    │
│                   • Lightweight transformations                          │
│                   • Event enrichment                                     │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     AWS GLUE SPARK JOBS                                  │
│                   ┌─────────────────────────────────────────────┐       │
│                   │  BRONZE LAYER (Raw CDC Events)               │       │
│                   │  • Full payload with before/after states    │       │
│                   │  • Schema: cdc_demo_dev_bronze_{table}      │       │
│                   └─────────────────────────────────────────────┘       │
│                   ┌─────────────────────────────────────────────┐       │
│                   │  SILVER LAYER (Cleaned & Standardized)       │       │
│                   │  • Deduplicated records                     │       │
│                   │  • Data quality flags                       │       │
│                   │  • Schema: cdc_demo_dev_silver_{table}      │       │
│                   └─────────────────────────────────────────────┘       │
│                   ┌─────────────────────────────────────────────┐       │
│                   │  GOLD LAYER (Analytics-Ready)               │       │
│                   │  • User analytics (segments, CLV)           │       │
│                   │  • Product analytics (revenue, popularity)  │       │
│                   │  • Sales trends and patterns                │       │
│                   │  • Schema: cdc_demo_dev_gold_*              │       │
│                   └─────────────────────────────────────────────┘       │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    APACHE ICEBERG (on S3)                                │
│                   • ACID transactions                                    │
│                   • Time travel queries                                  │
│                   • Schema evolution                                     │
│                   • Partition optimization                              │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        AWS SERVICES                                      │
│                   • Glue Data Catalog (metadata)                         │
│                   • Amazon Athena (SQL analytics)                        │
│                   • CloudWatch (monitoring)                              │
│                   • Secrets Manager (credentials)                        │
│                   • SNS/SQS (notifications)                              │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    APACHE AIRFLOW                                        │
│                   • Pipeline orchestration                               │
│                   • Scheduled batch jobs                                 │
│                   • Data quality monitoring                              │
│                   • Failure notifications                                │
└─────────────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Local Development
```bash
# Start all services (PostgreSQL, Kafka, Debezium)
./run.sh start

# Setup CDC connectors
./run.sh connectors

# Test CDC with sample operations
./run.sh test

# View CDC events in real-time
docker exec cdc-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic cdc.public.users \
  --from-beginning
```

### Deploy to AWS
```bash
# Configure AWS credentials
aws configure

# Deploy infrastructure
chmod +x deploy.sh
./deploy.sh

# Upload scripts and start processing
./deploy.sh scripts
./deploy.sh connector
./deploy.sh glue
```

## 📁 Project Structure

```
├── docker-compose.yml          # Local development environment
├── run.sh                      # Local development script
├── deploy.sh                   # AWS deployment script
├── requirements.txt            # Python dependencies
│
├── sql/
│   └── init.sql               # Database schema
│
├── airflow/
│   └── dags/
│       └── cdc_pipeline_dag.py # Airflow orchestration DAG
│
├── glue/
│   ├── cdc_processor.py       # Bronze/Silver layer processing
│   └── gold_processor.py      # Gold layer analytics
│
├── kafka_streams/
│   └── cdc_stream_processor.py # Real-time routing
│
├── scripts/
│   ├── debezium_connector.py   # Connector management
│   └── cost_optimization.sh    # Cost management
│
└── terraform/
    ├── main.tf                # Main infrastructure
    ├── variables.tf           # Variables
    └── modules/
        ├── vpc/               # Networking
        ├── s3/                # Data lake storage
        ├── kafka/             # MSK cluster
        ├── ecs/               # Debezium containers
        ├── glue/              # Spark jobs
        └── airflow/           # Orchestration
```

## 🎯 Key Features

| Feature | Description |
|---------|-------------|
| **Real-Time CDC** | Debezium captures every database change instantly |
| **Lakehouse Architecture** | Bronze/Silver/Gold layers with Apache Iceberg |
| **Serverless Processing** | AWS Glue for scalable Spark jobs |
| **Orchestration** | Apache Airflow for workflow management |
| **Cost Optimized** | Free tier compatible, auto-shutdown policies |
| **Production Ready** | Terraform modules, CI/CD, monitoring |

## 💰 Estimated Monthly Cost (AWS Free Tier)

| Service | Configuration | Cost |
|---------|--------------|------|
| MSK | kafka.t3.small (2 brokers) | ~$30 |
| ECS | 256 CPU / 512 MB | ~$7 |
| Glue | 2x G.1X workers | ~$15 |
| RDS | db.t3.micro | Free tier |
| S3 | Intelligent tiering | ~$1 |
| **Total** | | **~$53/month** |

## 📊 Medallion Architecture

### Bronze Layer (Raw CDC)
- Full CDC payload with before/after states
- All schema changes captured
- Stored as Parquet in S3 with Iceberg

### Silver Layer (Cleaned)
- Deduplicated records
- Data quality flags added
- Standardized data types
- Enriched with reference data

### Gold Layer (Analytics)
- User analytics (segments, CLV)
- Product analytics (popularity, revenue)
- Sales trends and patterns
- Aggregations and KPIs

## 🛠️ Technologies

| Layer | Technology |
|-------|------------|
| Source | PostgreSQL 15 |
| CDC | Debezium 2.4 |
| Streaming | Apache Kafka 3.5 (MSK) |
| Processing | Apache Spark 4.0 (Glue) |
| Storage | Apache Iceberg on S3 |
| Orchestration | Apache Airflow 2.7 |
| Infrastructure | Terraform, AWS |

## 📝 Usage

### Local Testing
```bash
# Connect to PostgreSQL
docker exec -it cdc-postgres psql -U postgres -d cdc_demo

# Execute CDC operations
INSERT INTO users (name, email) VALUES ('Test', 'test@example.com');
UPDATE users SET name = 'Updated' WHERE email = 'test@example.com';
DELETE FROM users WHERE email = 'test@example.com';

# Verify in Kafka
docker exec cdc-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic cdc.public.users \
  --from-beginning
```

### AWS Queries (Athena)
```sql
-- Bronze layer
SELECT * FROM "awsdatatalog"."cdc_demo_dev_bronze_users"
ORDER BY processed_at DESC LIMIT 100;

-- Silver layer
SELECT * FROM "awsdatatalog"."cdc_demo_dev_silver_users"
WHERE is_active = true;

-- Gold layer (User Analytics)
SELECT * FROM "awsdatatalog"."cdc_demo_dev_gold_user_analytics"
ORDER BY total_spent DESC LIMIT 10;
```

## 🔧 Configuration

### Local (.env)
```bash
# Edit docker-compose.yml or run.sh for local settings
```

### AWS (terraform/variables.tf)
```hcl
variable "project_name" {
  default = "cdc-pipeline"  # Change for your project
}

variable "environment" {
  default = "dev"           # dev, staging, prod
}

variable "alert_email" {
  default = "lokeshpatil8484@gmail.com"  # CHANGE THIS
}
```

## 🧹 Cleanup

### Local
```bash
docker-compose down -v
```

### AWS
```bash
./deploy.sh destroy
# OR
cd terraform && terraform destroy -auto-approve
```


