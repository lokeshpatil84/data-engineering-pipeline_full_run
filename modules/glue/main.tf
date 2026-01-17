# Glue Database
resource "aws_glue_catalog_database" "main" {
  name = "${var.project_name}_${var.environment}_db"

  description = "Database for CDC pipeline"

  tags = {
    Name = "${var.project_name}-${var.environment}-glue-db"
  }
}

# Glue Streaming Job
resource "aws_glue_job" "cdc_processor" {
  name         = "${var.project_name}-${var.environment}-cdc-processor"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"

  command {
    script_location = "s3://${var.s3_bucket_name}/scripts/cdc_processor.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"           = "s3://${var.s3_bucket_name}/logs/spark-events/"
    "--enable-continuous-cloudwatch-log" = "true"
    "--TempDir"                         = "s3://${var.s3_bucket_name}/temp/"
    "--DATABASE_NAME"                   = aws_glue_catalog_database.main.name
    "--S3_BUCKET"                       = var.s3_bucket_name
  }

  worker_type       = var.worker_type
  number_of_workers = var.number_of_workers
  timeout           = 2880  # 48 hours

  tags = {
    Name = "${var.project_name}-${var.environment}-cdc-processor"
  }
}

# Glue Streaming Job for Real-time Processing
resource "aws_glue_job" "realtime_processor" {
  name         = "${var.project_name}-${var.environment}-realtime-processor"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"

  command {
    script_location = "s3://${var.s3_bucket_name}/scripts/realtime_processor.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--enable-metrics"                   = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"           = "s3://${var.s3_bucket_name}/logs/spark-events/"
    "--enable-continuous-cloudwatch-log" = "true"
    "--TempDir"                         = "s3://${var.s3_bucket_name}/temp/"
    "--DATABASE_NAME"                   = aws_glue_catalog_database.main.name
    "--S3_BUCKET"                       = var.s3_bucket_name
  }

  worker_type       = var.worker_type
  number_of_workers = var.number_of_workers
  timeout           = 2880

  tags = {
    Name = "${var.project_name}-${var.environment}-realtime-processor"
  }
}

# IAM Role for Glue
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
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_policy" {
  name = "${var.project_name}-${var.environment}-glue-s3-policy"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      }
    ]
  })
}

# Glue Tables for Iceberg
resource "aws_glue_catalog_table" "users_bronze" {
  name          = "users_bronze"
  database_name = aws_glue_catalog_database.main.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "table_type"                = "ICEBERG"
    "metadata_location"         = "s3://${var.s3_bucket_name}/bronze/users/metadata/"
    "write.format.default"      = "parquet"
    "write.parquet.compression" = "snappy"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/bronze/users/"
    input_format  = "org.apache.iceberg.mr.hive.HiveIcebergInputFormat"
    output_format = "org.apache.iceberg.mr.hive.HiveIcebergOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.iceberg.mr.hive.HiveIcebergSerDe"
    }

    columns {
      name = "id"
      type = "bigint"
    }
    columns {
      name = "name"
      type = "string"
    }
    columns {
      name = "email"
      type = "string"
    }
    columns {
      name = "created_at"
      type = "timestamp"
    }
    columns {
      name = "updated_at"
      type = "timestamp"
    }
    columns {
      name = "op"
      type = "string"
    }
    columns {
      name = "ts_ms"
      type = "bigint"
    }
  }
}

resource "aws_glue_catalog_table" "users_silver" {
  name          = "users_silver"
  database_name = aws_glue_catalog_database.main.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "table_type"                = "ICEBERG"
    "metadata_location"         = "s3://${var.s3_bucket_name}/silver/users/metadata/"
    "write.format.default"      = "parquet"
    "write.parquet.compression" = "snappy"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/silver/users/"
    input_format  = "org.apache.iceberg.mr.hive.HiveIcebergInputFormat"
    output_format = "org.apache.iceberg.mr.hive.HiveIcebergOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.iceberg.mr.hive.HiveIcebergSerDe"
    }

    columns {
      name = "id"
      type = "bigint"
    }
    columns {
      name = "name"
      type = "string"
    }
    columns {
      name = "email"
      type = "string"
    }
    columns {
      name = "created_at"
      type = "timestamp"
    }
    columns {
      name = "updated_at"
      type = "timestamp"
    }
    columns {
      name = "is_active"
      type = "boolean"
    }
    columns {
      name = "processed_at"
      type = "timestamp"
    }
  }
}

resource "aws_glue_catalog_table" "users_gold" {
  name          = "users_gold"
  database_name = aws_glue_catalog_database.main.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "table_type"                = "ICEBERG"
    "metadata_location"         = "s3://${var.s3_bucket_name}/gold/users/metadata/"
    "write.format.default"      = "parquet"
    "write.parquet.compression" = "snappy"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/gold/users/"
    input_format  = "org.apache.iceberg.mr.hive.HiveIcebergInputFormat"
    output_format = "org.apache.iceberg.mr.hive.HiveIcebergOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.iceberg.mr.hive.HiveIcebergSerDe"
    }

    columns {
      name = "user_id"
      type = "bigint"
    }
    columns {
      name = "full_name"
      type = "string"
    }
    columns {
      name = "email_domain"
      type = "string"
    }
    columns {
      name = "registration_date"
      type = "date"
    }
    columns {
      name = "last_activity"
      type = "timestamp"
    }
    columns {
      name = "user_segment"
      type = "string"
    }
  }
}