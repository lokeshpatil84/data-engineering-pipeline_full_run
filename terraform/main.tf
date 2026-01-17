# =============================================================================
# CDC Pipeline - Main Terraform Configuration
# =============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Get default tags from variables
locals {
  common_tags = var.tags
}

# =============================================================================
# VPC Module - Network Infrastructure
# =============================================================================
module "vpc" {
  source = "./modules/vpc"

  project_name        = var.project_name
  environment         = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, var.availability_zones)
  tags               = var.tags
}

# =============================================================================
# S3 Module - Data Lake Storage
# =============================================================================
module "s3" {
  source = "./modules/s3"

  project_name              = var.project_name
  environment               = var.environment
  lifecycle_expiration_days = var.s3_lifecycle_expiration_days
  tags                      = var.tags
}

# =============================================================================
# Kafka Module - MSK Cluster
# =============================================================================
module "kafka" {
  source = "./modules/kafka"

  project_name           = var.project_name
  environment            = var.environment
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_subnet_ids
  instance_type         = var.msk_instance_type
  number_of_brokers     = var.msk_number_of_brokers
  volume_size           = var.msk_volume_size
  ecs_security_group_id = module.ecs.ecs_security_group_id
  aws_region            = var.aws_region
  tags                  = var.tags
}

# =============================================================================
# Secrets Manager - Database Credentials
# =============================================================================
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}-${var.environment}-db-credentials"
  description = "Database credentials for CDC pipeline"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.postgres.address
    port     = var.db_port
    database = var.db_name
  })
}

# =============================================================================
# RDS PostgreSQL - Source Database
# =============================================================================
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet"
  subnet_ids = module.vpc.private_subnet_ids

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "postgres" {
  identifier        = "${var.project_name}-${var.environment}-postgres"
  engine            = "postgres"
  engine_version    = "15.10"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = var.db_port

  vpc_security_group_ids = [module.vpc.postgres_security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  # Free tier compatible: backup_retention_period must be 0 or 7 max
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-postgres"
  })
}

# =============================================================================
# ECS Module - Debezium Container
# =============================================================================
module "ecs" {
  source = "./modules/ecs"

  project_name            = var.project_name
  environment             = var.environment
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnet_ids
  public_subnet_ids      = module.vpc.public_subnet_ids
  cpu                    = var.ecs_cpu
  memory                 = var.ecs_memory
  db_secret_arn          = aws_secretsmanager_secret.db_credentials.arn
  kafka_bootstrap_servers = module.kafka.bootstrap_brokers_tls
  aws_region             = var.aws_region
  tags                   = var.tags
  ecs_security_group_id  = module.vpc.ecs_security_group_id
}

# =============================================================================
# Glue Module - Spark Processing Jobs
# =============================================================================
module "glue" {
  source = "./modules/glue"

  project_name             = var.project_name
  environment              = var.environment
  s3_bucket_name          = module.s3.data_bucket_name
  worker_type             = var.glue_worker_type
  number_of_workers       = var.glue_number_of_workers
  glue_job_timeout        = var.glue_job_timeout
  aws_region              = var.aws_region
  tags                    = var.tags
}

# =============================================================================
# Airflow Module - Orchestration
# =============================================================================
module "airflow" {
  source = "./modules/airflow"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  s3_bucket_name     = module.s3.data_bucket_name
  aws_region         = var.aws_region
  tags               = var.tags
}

# =============================================================================
# SNS - Alerts and Notifications
# =============================================================================
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# =============================================================================
# CloudWatch - Cost Monitoring
# =============================================================================
resource "aws_cloudwatch_metric_alarm" "cost_alarm" {
  alarm_name          = "${var.project_name}-${var.environment}-cost-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"
  statistic           = "Maximum"
  threshold           = var.cost_threshold
  alarm_description   = "This metric monitors AWS estimated charges"

  dimensions = {
    Currency = "USD"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# =============================================================================
# Outputs
# =============================================================================
output "project_name" {
  value = var.project_name
}

output "environment" {
  value = var.environment
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "s3_data_lake_bucket" {
  value = module.s3.data_bucket_name
}

# MSK Bootstrap Servers - ENABLED after cluster is ACTIVE
output "msk_bootstrap_servers" {
  value     = module.kafka.bootstrap_servers
  sensitive = true
  description = "Plaintext MSK bootstrap servers (port 9092)"
}

output "msk_bootstrap_brokers_tls" {
  value     = module.kafka.bootstrap_brokers_tls
  sensitive = true
  description = "TLS MSK bootstrap servers (port 9094) - Use this for TLS auth"
}

output "msk_bootstrap_brokers_sasl_iam" {
  value     = module.kafka.bootstrap_brokers_sasl_iam
  sensitive = true
  description = "SASL/IAM MSK bootstrap servers (port 9098) - Use this for IAM auth"
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "debezium_connect_url" {
  value = "http://${module.ecs.alb_dns_name}:8083"
}

output "airflow_url" {
  value = "http://${module.airflow.alb_dns_name}"
}

output "glue_role_arn" {
  value = module.glue.role_arn
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "quick_start_commands" {
  sensitive = true
  value = <<-COMMANDS

  # After deployment, run these commands:

  # 1. Upload Glue scripts to S3
  aws s3 cp glue/ s3://${module.s3.data_bucket_name}/scripts/ --recursive

  # 2. Upload Airflow DAGs
  aws s3 cp airflow/dags/ s3://${module.s3.data_bucket_name}/dags/ --recursive

  # 3. Register Debezium connector
  curl -X PUT "http://${module.ecs.alb_dns_name}:8083/connectors/cdc-connector/config" \\
    -H "Content-Type: application/json" \\
    -d '{
      "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
      "database.hostname": "${aws_db_instance.postgres.address}",
      "database.port": "5432",
      "database.user": "${var.db_username}",
      "database.password": "${var.db_password}",
      "database.dbname": "${var.db_name}",
      "database.server.name": "cdc-server",
      "topic.prefix": "cdc",
      "table.include.list": "public.users,public.products,public.orders",
      "plugin.name": "pgoutput"
    }'

  # 4. Start Glue jobs
  aws glue start-job-run --job-name ${var.project_name}-${var.environment}-cdc-processor
  aws glue start-job-run --job-name ${var.project_name}-${var.environment}-gold-processor

  COMMANDS
}

