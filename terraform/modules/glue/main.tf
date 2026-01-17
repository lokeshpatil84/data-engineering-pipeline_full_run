# =============================================================================
# Glue Jobs for CDC Processing - Fixed for Iceberg Support
# =============================================================================

# IAM Role for Glue Jobs
resource "aws_iam_role" "glue_role" {
  name = "${var.project_name}-${var.environment}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-glue-role"
  })
}

# Glue Service Policy
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# S3 Access Policy for Glue - Using data_bucket_name from S3 module
resource "aws_iam_policy" "glue_s3_policy" {
  name = "${var.project_name}-${var.environment}-glue-s3-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Action = [
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = "arn:aws:s3:::${var.s3_bucket_name}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_s3" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_s3_policy.arn
}

# CloudWatch Logs Policy for Glue
resource "aws_iam_policy" "glue_logs_policy" {
  name = "${var.project_name}-${var.environment}-glue-logs-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:log-group:/aws/glue/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_logs" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_logs_policy.arn
}

# Glue Catalog Policy for Iceberg support
resource "aws_iam_policy" "glue_catalog_policy" {
  name = "${var.project_name}-${var.environment}-glue-catalog-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:CreateDatabase",
          "glue:GetTable",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:GetPartitions",
          "glue:CreatePartition",
          "glue:BatchCreatePartition"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_catalog" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_catalog_policy.arn
}

# MSK Kafka Access Policy for Glue (IAM authentication)
resource "aws_iam_policy" "glue_msk_policy" {
  name = "${var.project_name}-${var.environment}-glue-msk-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka:DescribeCluster",
          "kafka:GetBootstrapBrokers",
          "kafka:DescribeTopic",
          "kafka:ListTopics"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_msk" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_msk_policy.arn
}

# =============================================================================
# CDC Processor Job - Fixed Configuration for Iceberg
# =============================================================================
resource "aws_glue_job" "cdc_processor" {
  name        = "${var.project_name}-${var.environment}-cdc-processor"
  role_arn    = aws_iam_role.glue_role.arn
  glue_version = "4.0"

  command {
    python_version = "3"
    script_location = "s3://${var.s3_bucket_name}/scripts/cdc_processor.py"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  default_arguments = {
    "--JOB_NAME"              = "${var.project_name}-${var.environment}-cdc-processor"
    "--DATABASE_NAME"         = "cdc_demo"
    "--S3_BUCKET"             = var.s3_bucket_name
    "--REGION"                = var.aws_region
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"        = ""
    "--additional-python-modules" = "pyiceberg==0.5.1"
    
    # Iceberg Configuration - FIXED: Separate --conf flags
    "--conf"                  = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
    "--conf"                  = "spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog"
    "--conf"                  = "spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog"
    "--conf"                  = "spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO"
    "--conf"                  = "spark.sql.catalog.glue_catalog.warehouse=s3://${var.s3_bucket_name}/iceberg-warehouse/"
  }

  worker_type       = var.worker_type
  number_of_workers = var.number_of_workers
  timeout           = var.glue_job_timeout

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-cdc-processor"
  })
}

# =============================================================================
# Gold Processor Job - Fixed Configuration for Iceberg
# =============================================================================
resource "aws_glue_job" "gold_processor" {
  name        = "${var.project_name}-${var.environment}-gold-processor"
  role_arn    = aws_iam_role.glue_role.arn
  glue_version = "4.0"

  command {
    python_version = "3"
    script_location = "s3://${var.s3_bucket_name}/scripts/gold_processor.py"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  default_arguments = {
    "--JOB_NAME"              = "${var.project_name}-${var.environment}-gold-processor"
    "--DATABASE_NAME"         = "cdc_demo"
    "--S3_BUCKET"             = var.s3_bucket_name
    "--REGION"                = var.aws_region
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"        = ""
    "--additional-python-modules" = "pyiceberg==0.5.1"
    
    # Iceberg Configuration - FIXED: Separate --conf flags
    "--conf"                  = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
    "--conf"                  = "spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog"
    "--conf"                  = "spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog"
    "--conf"                  = "spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO"
    "--conf"                  = "spark.sql.catalog.glue_catalog.warehouse=s3://${var.s3_bucket_name}/iceberg-warehouse/"
  }

  worker_type       = var.worker_type
  number_of_workers = var.number_of_workers
  timeout           = var.glue_job_timeout

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-gold-processor"
  })
}

# =============================================================================
# Glue Database and Resources
# =============================================================================

# Glue Database (Data Catalog)
resource "aws_glue_catalog_database" "data_lake" {
  name        = "${var.project_name}_${var.environment}_data_lake"
  description = "CDC Pipeline Data Lake Database"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-glue-db"
  })
}

# CloudWatch Log Group for Glue
resource "aws_cloudwatch_log_group" "glue" {
  name              = "/aws/glue/${var.project_name}-${var.environment}"
  retention_in_days = 30

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-glue-logs"
  })
}

