variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs"
  type        = list(string)
}

variable "s3_bucket_name" {
  description = "S3 bucket name"
  type        = string
}

output "cluster_name" {
  description = "Airflow ECS cluster name"
  value       = aws_ecs_cluster.airflow.name
}

output "service_name" {
  description = "Airflow ECS service name"
  value       = aws_ecs_service.airflow.name
}

output "task_execution_role_arn" {
  description = "Airflow task execution role ARN"
  value       = aws_iam_role.task_execution.arn
}

output "web_url" {
  description = "Airflow web UI URL"
  value       = "http://${aws_lb.airflow.dns_name}"
}

output "load_balancer_dns" {
  description = "Load balancer DNS name"
  value       = aws_lb.airflow.dns_name
}
