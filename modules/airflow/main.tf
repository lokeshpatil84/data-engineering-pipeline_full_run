# ECS Task Definition for Airflow
resource "aws_ecs_task_definition" "airflow" {
  family                   = "${var.project_name}-${var.environment}-airflow"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.airflow_execution_role.arn
  task_role_arn           = aws_iam_role.airflow_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "airflow-webserver"
      image = "apache/airflow:2.7.0"
      
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "AIRFLOW__CORE__EXECUTOR"
          value = "LocalExecutor"
        },
        {
          name  = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN"
          value = "sqlite:////opt/airflow/airflow.db"
        },
        {
          name  = "AIRFLOW__CORE__DAGS_FOLDER"
          value = "/opt/airflow/dags"
        },
        {
          name  = "AIRFLOW__WEBSERVER__EXPOSE_CONFIG"
          value = "true"
        },
        {
          name  = "AWS_DEFAULT_REGION"
          value = data.aws_region.current.name
        },
        {
          name  = "S3_BUCKET"
          value = var.s3_bucket_name
        }
      ]

      command = ["bash", "-c", "airflow db init && airflow users create --username admin --firstname Admin --lastname User --role Admin --email admin@example.com --password admin && airflow webserver"]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.airflow.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-${var.environment}-airflow-task"
  }
}

# ECS Service for Airflow
resource "aws_ecs_service" "airflow" {
  name            = "${var.project_name}-${var.environment}-airflow"
  cluster         = aws_ecs_cluster.airflow.id
  task_definition = aws_ecs_task_definition.airflow.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.airflow.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.airflow.arn
    container_name   = "airflow-webserver"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.airflow]

  tags = {
    Name = "${var.project_name}-${var.environment}-airflow-service"
  }
}

# ECS Cluster for Airflow
resource "aws_ecs_cluster" "airflow" {
  name = "${var.project_name}-${var.environment}-airflow-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-airflow-cluster"
  }
}

# Application Load Balancer
resource "aws_lb" "airflow" {
  name               = "${var.project_name}-${var.environment}-airflow-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-${var.environment}-airflow-alb"
  }
}

resource "aws_lb_target_group" "airflow" {
  name        = "${var.project_name}-${var.environment}-airflow-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-airflow-tg"
  }
}

resource "aws_lb_listener" "airflow" {
  load_balancer_arn = aws_lb.airflow.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.airflow.arn
  }
}

# Security Groups
resource "aws_security_group" "airflow" {
  name_prefix = "${var.project_name}-${var.environment}-airflow-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-airflow-sg"
  }
}

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.environment}-alb-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "airflow" {
  name              = "/ecs/${var.project_name}-${var.environment}-airflow"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-airflow-logs"
  }
}

# IAM Roles
resource "aws_iam_role" "airflow_execution_role" {
  name = "${var.project_name}-${var.environment}-airflow-execution-role"

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

resource "aws_iam_role_policy_attachment" "airflow_execution_role_policy" {
  role       = aws_iam_role.airflow_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "airflow_task_role" {
  name = "${var.project_name}-${var.environment}-airflow-task-role"

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

resource "aws_iam_role_policy" "airflow_task_policy" {
  name = "${var.project_name}-${var.environment}-airflow-task-policy"
  role = aws_iam_role.airflow_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "glue:BatchStopJobRun"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      }
    ]
  })
}

data "aws_region" "current" {}

# Get public subnets (assuming they exist in the VPC module)
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  tags = {
    Type = "Public"
  }
}