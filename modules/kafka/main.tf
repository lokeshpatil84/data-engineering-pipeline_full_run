# MSK Cluster Configuration
resource "aws_msk_configuration" "main" {
  kafka_versions = ["2.8.1"]
  name           = "${var.project_name}-${var.environment}-msk-config"

  server_properties = <<PROPERTIES
auto.create.topics.enable=true
default.replication.factor=2
min.insync.replicas=1
num.partitions=3
log.retention.hours=168
log.segment.bytes=1073741824
PROPERTIES
}

# MSK Cluster
resource "aws_msk_cluster" "main" {
  cluster_name           = "${var.project_name}-${var.environment}-msk"
  kafka_version          = "2.8.1"
  number_of_broker_nodes = 2

  broker_node_group_info {
    instance_type   = "kafka.t3.small"  # Free tier eligible
    client_subnets  = var.subnet_ids
    security_groups = [aws_security_group.msk.id]
    
    storage_info {
      ebs_storage_info {
        volume_size = 10  # Minimum size
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.main.arn
    revision = aws_msk_configuration.main.latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "PLAINTEXT"
      in_cluster    = false
    }
  }

  client_authentication {
    unauthenticated = true
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-msk"
  }
}

# Security Group for MSK
resource "aws_security_group" "msk" {
  name_prefix = "${var.project_name}-${var.environment}-msk-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-msk-sg"
  }
}

# CloudWatch Log Group for MSK
resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.project_name}-${var.environment}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-msk-logs"
  }
}

# Kafka Topics (using Lambda for topic creation)
resource "aws_lambda_function" "kafka_topic_manager" {
  filename         = "kafka_topic_manager.zip"
  function_name    = "${var.project_name}-${var.environment}-kafka-topic-manager"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      BOOTSTRAP_SERVERS = aws_msk_cluster.main.bootstrap_brokers
    }
  }

  depends_on = [data.archive_file.kafka_topic_manager]

  tags = {
    Name = "${var.project_name}-${var.environment}-kafka-topic-manager"
  }
}

# Lambda deployment package
data "archive_file" "kafka_topic_manager" {
  type        = "zip"
  output_path = "kafka_topic_manager.zip"
  
  source {
    content = <<EOF
import json
import boto3
from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import TopicAlreadyExistsError
import os

def handler(event, context):
    bootstrap_servers = os.environ['BOOTSTRAP_SERVERS'].split(',')
    
    admin_client = KafkaAdminClient(
        bootstrap_servers=bootstrap_servers,
        client_id='topic-manager'
    )
    
    topics = [
        NewTopic(name='cdc.users', num_partitions=3, replication_factor=2),
        NewTopic(name='cdc.products', num_partitions=3, replication_factor=2),
        NewTopic(name='cdc.orders', num_partitions=3, replication_factor=2),
        NewTopic(name='processed.users', num_partitions=3, replication_factor=2),
        NewTopic(name='processed.products', num_partitions=3, replication_factor=2),
        NewTopic(name='processed.orders', num_partitions=3, replication_factor=2)
    ]
    
    try:
        admin_client.create_topics(topics, validate_only=False)
        return {
            'statusCode': 200,
            'body': json.dumps('Topics created successfully')
        }
    except TopicAlreadyExistsError:
        return {
            'statusCode': 200,
            'body': json.dumps('Topics already exist')
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    filename = "index.py"
  }
}

# Lambda IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-${var.environment}-lambda-kafka-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security Group for Lambda
resource "aws_security_group" "lambda" {
  name_prefix = "${var.project_name}-${var.environment}-lambda-"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-lambda-sg"
  }
}

# Invoke Lambda to create topics
resource "aws_lambda_invocation" "create_topics" {
  function_name = aws_lambda_function.kafka_topic_manager.function_name

  input = jsonencode({
    action = "create_topics"
  })

  depends_on = [aws_msk_cluster.main]
}