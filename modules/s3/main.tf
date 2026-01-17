# S3 Bucket for Data Lake
resource "aws_s3_bucket" "data_lake" {
  bucket = "${var.project_name}-${var.environment}-datalake-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.project_name}-${var.environment}-datalake"
    Purpose     = "Data Lake Storage"
    DataTier    = "All"
  }
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Bucket Versioning
resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Intelligent Tiering for Cost Optimization
resource "aws_s3_bucket_intelligent_tiering_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  name   = "EntireBucket"

  status = "Enabled"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }
}

# Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "bronze_tier_lifecycle"
    status = "Enabled"

    filter {
      prefix = "bronze/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "silver_tier_lifecycle"
    status = "Enabled"

    filter {
      prefix = "silver/"
    }

    transition {
      days          = 60
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "logs_cleanup"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    expiration {
      days = 30
    }
  }
}

# Create folder structure
resource "aws_s3_object" "bronze_folder" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "bronze/"
}

resource "aws_s3_object" "silver_folder" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "silver/"
}

resource "aws_s3_object" "gold_folder" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "gold/"
}

resource "aws_s3_object" "scripts_folder" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "scripts/"
}

resource "aws_s3_object" "logs_folder" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "logs/"
}

# Outputs
output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.data_lake.bucket
}

output "data_bucket_name" {
  description = "S3 bucket name (alias for compatibility)"
  value       = aws_s3_bucket.data_lake.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.data_lake.arn
}

output "bucket_domain_name" {
  description = "S3 bucket domain name"
  value       = aws_s3_bucket.data_lake.bucket_domain_name
}
