# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cluster"
  }
}

# ECS Task Definition for Debezium
resource "aws_ecs_task_definition" "debezium" {
  family                   = "${var.project_name}-${var.environment}-debezium"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "debezium-connect"
      image = "debezium/connect:2.4"
      
      portMappings = [
        {
          containerPort = 8083
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "BOOTSTRAP_SERVERS"
          value = var.kafka_bootstrap_servers
        },
        {
          name  = "GROUP_ID"
          value = "debezium-cluster"
        },
        {
          name  = "CONFIG_STORAGE_TOPIC"
          value = "debezium-configs"
        },
        {
          name  = "OFFSET_STORAGE_TOPIC"
          value = "debezium-offsets"
        },
        {
          name  = "STATUS_STORAGE_TOPIC"
          value = "debezium-status"
        }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.db_secret_arn}:password::"
        },
        {
          name      = "DB_USERNAME"
          valueFrom = "${var.db_secret_arn}:username::"
        },
        {
          name      = "DB_HOST"
          valueFrom = "${var.db_secret_arn}:host::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.debezium.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-${var.environment}-debezium-task"
  }
}

# ECS Service
resource "aws_ecs_service" "debezium" {
  name            = "${var.project_name}-${var.environment}-debezium"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.debezium.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.debezium.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.debezium.arn
  }
}

# Security Group for Debezium
resource "aws_security_group" "debezium" {
  name_prefix = "${var.project_name}-${var.environment}-debezium-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8083
    to_port     = 8083
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
    Name = "${var.project_name}-${var.environment}-debezium-sg"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "debezium" {
  name              = "/ecs/${var.project_name}-${var.environment}-debezium"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-debezium-logs"
  }
}

# Service Discovery
resource "aws_service_discovery_private_dns_namespace" "main" {
  name = "${var.project_name}-${var.environment}.local"
  vpc  = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-namespace"
  }
}

resource "aws_service_discovery_service" "debezium" {
  name = "debezium"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_config {
    type = "TCP"
  }
}

# IAM Roles
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-${var.environment}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_secrets_policy" {
  name = "${var.project_name}-${var.environment}-ecs-secrets-policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [var.db_secret_arn]
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

data "aws_region" "current" {}

