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
  description = "Private subnet IDs for MSK brokers"
  type        = list(string)
}

output "cluster_arn" {
  description = "MSK cluster ARN"
  value       = aws_msk_cluster.main.arn
}

output "bootstrap_servers" {
  description = "MSK bootstrap servers"
  value       = aws_msk_cluster.main.bootstrap_brokers
  sensitive   = true
}

output "bootstrap_brokers" {
  description = "MSK bootstrap brokers"
  value       = aws_msk_cluster.main.bootstrap_brokers
  sensitive   = true
}

output "zookeeper_connect_string" {
  description = "MSK Zookeeper connection string"
  value       = aws_msk_cluster.main.zookeeper_connect_string
}
