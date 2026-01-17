# Kafka Module Variables
variable "project_name" {
  type        = string
  description = "Project name"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs"
}

variable "instance_type" {
  type        = string
  default     = "kafka.t3.small"
  description = "MSK broker instance type"
}

variable "number_of_brokers" {
  type        = number
  default     = 2
  description = "Number of MSK brokers"
}

variable "volume_size" {
  type        = number
  default     = 20
  description = "Broker volume size in GB"
}

variable "ecs_security_group_id" {
  type        = string
  description = "ECS security group ID"
  default     = ""
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ap-south-1"
}

variable "tags" {
  type        = map(string)
  default = {
    Project     = "cdc-pipeline"
    Environment = "dev"
  }
}

