# S3 Module Outputs
output "data_bucket_name" {
  value = aws_s3_bucket.data_lake.bucket
}

output "data_bucket_arn" {
  value = aws_s3_bucket.data_lake.arn
}

output "glue_scripts_bucket" {
  value = aws_s3_bucket.glue_scripts.bucket
}



