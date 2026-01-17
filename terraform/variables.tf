# Terraform variables - customize these for your environment
# make sure to change defaults before production use!

# -----------------------------------------------------------------------------
# Project Basics
# -----------------------------------------------------------------------------
variable "project_name" {
  type    = string
  default = "data-engineer"  # matched to existing state resources
}

variable "environment" {
  type    = string
  default = "dev"           # dev, staging, or prod
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"    # change to your preferred region
}

# -----------------------------------------------------------------------------
# VPC Network - adjust CIDR if you have overlapping networks
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = number
  default = 2               # using 2 AZs for cost optimization
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL - FREE TIER compatible settings
# NOTE: change db_password before deploying to production!
# -----------------------------------------------------------------------------
variable "db_username" {
  type    = string
  default = "postgres"
}

variable "db_password" {
  type      = string
  default   = "postgres123!"
  sensitive = true         # password won't show in logs
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"  # free tier eligible
}

variable "db_name" {
  type    = string
  default = "cdc_demo"     # database name
}

variable "db_port" {
  type    = number
  default = 5432           # standard postgres port
}

# this will be set after RDS is created
variable "db_host" {
  type    = string
  default = ""             # filled by terraform after RDS creation
}

# -----------------------------------------------------------------------------
# ECS Fargate for Debezium
# -----------------------------------------------------------------------------
variable "ecs_cpu" {
  type    = number
  default = 256             # minimum for debezium
}

variable "ecs_memory" {
  type    = number
  default = 512             # 512MB should work for basic CDC
}

variable "ecs_desired_count" {
  type    = number
  default = 1               # single instance for dev
}

# -----------------------------------------------------------------------------
# MSK Kafka - managed kafka service
# t3.small is the smallest/cheapest option
# -----------------------------------------------------------------------------
variable "msk_instance_type" {
  type    = string
  default = "kafka.t3.small"
}

variable "msk_number_of_brokers" {
  type    = number
  default = 2               # minimum for high availability
}

variable "msk_volume_size" {
  type    = number
  default = 20              # 20GB per broker
}

# -----------------------------------------------------------------------------
# AWS Glue - spark jobs for processing
# G.1X workers give good balance of cost/performance
# -----------------------------------------------------------------------------
variable "glue_worker_type" {
  type    = string
  default = "G.1X"
}

variable "glue_number_of_workers" {
  type    = number
  default = 2
}

variable "glue_job_timeout" {
  type    = number
  default = 120             # 2 hours max
}

# -----------------------------------------------------------------------------
# Cost Controls
# -----------------------------------------------------------------------------
variable "cost_threshold" {
  type    = number
  default = 50              # alert if monthly cost exceeds $50
}

variable "alert_email" {
  type    = string
  default = "alerts@demo.local"  # CHANGE THIS for production!
}

# -----------------------------------------------------------------------------
# Common tags - applied to all resources
# -----------------------------------------------------------------------------
variable "tags" {
  type = map(string)
  default = {
    Project     = "cdc-pipeline"
    Environment = "dev"
    ManagedBy   = "terraform"
    Owner       = "data-engineering-team"
  }
}

# -----------------------------------------------------------------------------
# S3 Lifecycle
# -----------------------------------------------------------------------------
variable "s3_lifecycle_expiration_days" {
  type    = number
  default = 365
}

