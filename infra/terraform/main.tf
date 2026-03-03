# ============================================================
#  OcadoFlow — AWS Infrastructure (Terraform)
#  Author : Stanislav Vainer
#  Stack  : API Gateway + 3 ECS Microservices + IAM + VPC
# ============================================================

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "ocadoflow-terraform-state"
    key            = "infra/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "ocadoflow-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "OcadoFlow"
      ManagedBy   = "Terraform"
      Owner       = "stanislav.vainer"
      Environment = var.environment
    }
  }
}

# ── Variables ──────────────────────────────────────────────
variable "aws_region"   { default = "eu-west-1" }
variable "environment"  { default = "production" }
variable "app_name"     { default = "ocadoflow" }
variable "vpc_cidr"     { default = "10.0.0.0/16" }
variable "az_count"     { default = 2 }

variable "services" {
  description = "Microservice definitions"
  type = map(object({
    port           = number
    cpu            = number
    memory         = number
    desired_count  = number
    health_path    = string
  }))
  default = {
    products = { port=8081, cpu=256, memory=512, desired_count=2, health_path="/health" }
    orders   = { port=8082, cpu=512, memory=1024, desired_count=3, health_path="/health" }
    iam      = { port=8083, cpu=256, memory=512, desired_count=2, health_path="/health" }
  }
}

# ── VPC & Networking ───────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"

  name = "${var.app_name}-vpc"
  cidr = var.vpc_cidr

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = false   # HA: one per AZ
  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs → CloudWatch
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60
}

# ── Security Groups ────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.app_name}-alb-sg"
  description = "API Gateway / ALB — public HTTPS only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS inbound"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_services" {
  name        = "${var.app_name}-ecs-sg"
  description = "ECS services — ALB traffic only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8090
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "ALB to services"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── Application Load Balancer (API Gateway) ────────────────
resource "aws_lb" "gateway" {
  name               = "${var.app_name}-gateway"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = true
  enable_http2               = true

  access_logs {
    bucket  = aws_s3_bucket.logs.id
    prefix  = "alb"
    enabled = true
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.gateway.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.gateway.arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = jsonencode({ error="Not Found", code="ERR_ROUTE_NOT_FOUND" })
      status_code  = "404"
    }
  }
}

# Route rules: /api/v1/products/* → products, /api/v1/orders/* → orders, /api/v1/iam/* → iam
resource "aws_lb_listener_rule" "service_routes" {
  for_each     = var.services
  listener_arn = aws_lb_listener.https.arn
  priority     = index(keys(var.services), each.key) * 10 + 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services[each.key].arn
  }
  condition {
    path_pattern { values = ["/api/v1/${each.key}/*", "/api/v1/${each.key}"] }
  }
}

# ── ECS Cluster ────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# ── ECS Services (per microservice) ───────────────────────
resource "aws_ecs_task_definition" "services" {
  for_each = var.services

  family                   = "${var.app_name}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task[each.key].arn

  container_definitions = jsonencode([{
    name      = each.key
    image     = "${aws_ecr_repository.services[each.key].repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = each.value.port, protocol = "tcp" }]
    environment = [
      { name="SERVICE_NAME",  value=each.key },
      { name="ENVIRONMENT",   value=var.environment },
      { name="OAUTH2_ISSUER", value="https://auth.ocadoflow.io" }
    ]
    secrets = [
      { name="DB_PASSWORD",   valueFrom="${aws_secretsmanager_secret.db_passwords[each.key].arn}" },
      { name="JWT_SECRET",    valueFrom="${aws_secretsmanager_secret.jwt_secret.arn}" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.app_name}/${each.key}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${each.value.port}${each.value.health_path} || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}

resource "aws_ecs_service" "services" {
  for_each = var.services

  name            = "${var.app_name}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.services[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.services[each.key].arn
    container_name   = each.key
    container_port   = each.value.port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle { ignore_changes = [desired_count] }
}

# ── Auto Scaling ───────────────────────────────────────────
resource "aws_appautoscaling_target" "services" {
  for_each = var.services

  max_capacity       = 10
  min_capacity       = each.value.desired_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.services[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each = var.services

  name               = "${each.key}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# ── IAM — Least-Privilege Roles ───────────────────────────
resource "aws_iam_role" "ecs_execution" {
  name = "${var.app_name}-ecs-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Per-service task roles (least privilege — each service only gets what it needs)
resource "aws_iam_role" "ecs_task" {
  for_each = var.services
  name     = "${var.app_name}-${each.key}-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_secrets" {
  for_each = var.services
  name     = "${each.key}-secrets-access"
  role     = aws_iam_role.ecs_task[each.key].id
  policy   = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.db_passwords[each.key].arn,
        aws_secretsmanager_secret.jwt_secret.arn
      ]
    }]
  })
}

# ── ECR Repositories ───────────────────────────────────────
resource "aws_ecr_repository" "services" {
  for_each             = var.services
  name                 = "${var.app_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration     { encryption_type = "KMS" }
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = var.services
  repository = aws_ecr_repository.services[each.key].name
  policy     = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection    = { tagStatus="any", countType="imageCountMoreThan", countNumber=10 }
      action       = { type="expire" }
    }]
  })
}

# ── Secrets Manager ────────────────────────────────────────
resource "aws_secretsmanager_secret" "db_passwords" {
  for_each                = var.services
  name                    = "${var.app_name}/${var.environment}/${each.key}/db-password"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name                    = "${var.app_name}/${var.environment}/jwt-secret"
  recovery_window_in_days = 7
}

# ── S3 Logs Bucket ─────────────────────────────────────────
resource "aws_s3_bucket" "logs" {
  bucket        = "${var.app_name}-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
  }
}

# ── CloudWatch Alarms ──────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "service_cpu_high" {
  for_each = var.services

  alarm_name          = "${var.app_name}-${each.key}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU > 80% for ${each.key}"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.services[each.key].name
  }
}

resource "aws_sns_topic" "alerts" {
  name              = "${var.app_name}-alerts"
  kms_master_key_id = "alias/aws/sns"
}

# ── Outputs ────────────────────────────────────────────────
data "aws_caller_identity" "current" {}

output "gateway_url"    { value = "https://${aws_lb.gateway.dns_name}" }
output "cluster_name"   { value = aws_ecs_cluster.main.name }
output "ecr_repos"      { value = { for k,v in aws_ecr_repository.services : k => v.repository_url } }
