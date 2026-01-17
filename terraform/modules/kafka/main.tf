# Get current AWS account ID for KMS policy
data "aws_caller_identity" "current" {}

# MSK Kafka Cluster
resource "aws_msk_cluster" "main" {
  cluster_name           = "${var.project_name}-${var.environment}-msk"
  kafka_version          = "3.5.1"
  number_of_broker_nodes = var.number_of_brokers

  broker_node_group_info {
    instance_type   = var.instance_type
    client_subnets  = var.subnet_ids
    storage_info {
      ebs_storage_info {
        volume_size = var.volume_size
      }
    }
    security_groups = [aws_security_group.kafka.id]
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.main.arn
    revision = aws_msk_configuration.main.latest_revision
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-msk"
  })
}

# MSK Configuration
resource "aws_msk_configuration" "main" {
  name = "${var.project_name}-${var.environment}-msk-config"

  kafka_versions = ["3.5.1"]

  server_properties = <<-PROPS
    auto.create.topics.enable=true
    delete.topic.enable=true
    log.retention.hours=168
    num.partitions=3
    default.replication.factor=2
    min.insync.replicas=1
  PROPS
}

# KMS Key for encryption
# IMPORTANT: Key policy must allow root account to manage the key in future
resource "aws_kms_key" "msk" {
  description = "KMS key for MSK encryption"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow root account full access to manage the key
        # This is required to allow future key policy updates
        Sid = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "kms:*"
        Resource = "*"
      },
      {
        Sid = "Allow access for MSK"
        Effect = "Allow"
        Principal = {
          Service = "kafka.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# Security Group for MSK
resource "aws_security_group" "kafka" {
  name        = "${var.project_name}-${var.environment}-kafka-sg"
  description = "Security group for Kafka/MSK"
  vpc_id      = var.vpc_id

  # Allow traffic within the security group (broker-to-broker)
  ingress {
    from_port = 9092
    to_port   = 9092
    protocol  = "tcp"
    self      = true
  }

  # Allow traffic from ECS tasks
  ingress {
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [var.ecs_security_group_id]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-kafka-sg"
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "msk" {
  name = "/aws/msk/${var.project_name}-${var.environment}"
  retention_in_days = 30

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-msk-logs"
  })
}

