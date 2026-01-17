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

variable "subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "cpu" {
  description = "ECS task CPU"
  type        = number
  default     = 256
}

variable "memory" {
  description = "ECS task memory"
  type        = number
  default     = 512
}

variable "ecs_cpu" {
  description = "ECS task CPU (alias for cpu)"
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "ECS task memory (alias for memory)"
  type        = number
  default     = 512
}

variable "db_secret_arn" {
  description = "Database secret ARN from Secrets Manager"
  type        = string
}

variable "kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers"
  type        = string
  default     = ""
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.debezium.name
}

output "task_definition_arn" {
  description = "ECS task definition ARN"
  value       = aws_ecs_task_definition.debezium.arn
}

output "task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.task_execution.arn
}
