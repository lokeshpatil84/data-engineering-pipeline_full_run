variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.data_lake.bucket
}

output "data_bucket_name" {
  description = "S3 data lake bucket name (same as bucket_name)"
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
