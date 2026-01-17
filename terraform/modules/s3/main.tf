# S3 Data Lake Bucket
resource "aws_s3_bucket" "data_lake" {
  bucket = "${var.project_name}-${var.environment}-data-lake"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-data-lake"
  })
}

# Enable versioning for data safety
resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule - move to Glacier after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id = "archive-old-data"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = var.lifecycle_expiration_days
    }
  }
}

# S3 Bucket for Glue scripts
resource "aws_s3_bucket" "glue_scripts" {
  bucket = "${var.project_name}-${var.environment}-glue-scripts"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-glue-scripts"
  })
}

# S3 Bucket for logs
resource "aws_s3_bucket" "logs" {
  bucket = "${var.project_name}-${var.environment}-logs"

  # Enable ACLs for log delivery (required for log-delivery-write)
  # Note: When using bucket policies for logs, we don't need bucket ACLs
  lifecycle {
    prevent_destroy = false
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-logs"
  })
}

# Note: Removed aws_s3_bucket_acl resource because the bucket has 
# block_public_acls = true (from aws_s3_bucket_public_access_block)
# S3 buckets with Object Ownership set to "Bucket owner enforced" don't support ACLs

# Note: IAM Role for Glue is now defined in modules/glue/main.tf to avoid duplication
# The S3 module only manages S3 buckets, not IAM roles




resource "aws_s3_bucket" "my_s3" {
   
}