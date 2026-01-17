variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name for data lake"
  type        = string
}

variable "worker_type" {
  description = "Glue worker type"
  type        = string
  default     = "G.1X"
}

variable "number_of_workers" {
  description = "Number of Glue workers"
  type        = number
  default     = 2
}

output "database_name" {
  description = "Glue database name"
  value       = aws_glue_catalog_database.main.name
}

output "cdc_job_name" {
  description = "Glue CDC job name"
  value       = aws_glue_job.cdc_processor.name
}

output "gold_job_name" {
  description = "Glue Gold job name"
  value       = aws_glue_job.realtime_processor.name
}

output "role_arn" {
  description = "Glue IAM role ARN"
  value       = aws_iam_role.glue_role.arn
}
