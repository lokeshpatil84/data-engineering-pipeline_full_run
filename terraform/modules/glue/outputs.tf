# Glue Module Outputs
output "cdc_job_name" {
  value = aws_glue_job.cdc_processor.name
}

output "gold_job_name" {
  value = aws_glue_job.gold_processor.name
}

output "role_arn" {
  value = aws_iam_role.glue_role.arn
}

output "role_name" {
  value = aws_iam_role.glue_role.name
}

output "database_name" {
  value = aws_glue_catalog_database.data_lake.name
}

