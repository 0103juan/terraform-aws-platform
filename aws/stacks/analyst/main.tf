# Everything one environment of the agent service needs, composed from the modules. An environment is this
# stack with its own values and its own state (see envs/): nothing is shared between two of them.

locals {
  name = "analyst-${var.environment}"
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  region             = var.region
  cidr               = var.cidr
  availability_zones = var.availability_zones
  single_nat_gateway = var.single_nat_gateway

  # How a load balancer controller in the cluster finds the subnets it may use.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

module "eks" {
  source = "../../modules/eks"

  name                = local.name
  kubernetes_version  = var.kubernetes_version
  subnet_ids          = module.network.private_subnet_ids
  api_allowed_cidrs   = var.api_allowed_cidrs
  admin_role_arns     = var.admin_role_arns
  node_instance_types = var.nodes.instance_types
  node_capacity_type  = var.nodes.capacity_type
  node_count          = { min = var.nodes.min, max = var.nodes.max }
}

module "postgres" {
  source = "../../modules/postgres"

  name                       = local.name
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.database_subnet_ids
  allowed_security_group_ids = { cluster = module.eks.cluster_security_group_id }
  database_name              = "secop"
  instance_class             = var.database.instance_class
  multi_az                   = var.database.multi_az
  backup_retention_days      = var.database.backup_retention_days
  deletion_protection        = var.database.deletion_protection
}

module "redis" {
  source = "../../modules/redis"

  name                       = local.name
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.database_subnet_ids
  allowed_security_group_ids = { cluster = module.eks.cluster_security_group_id }
  node_type                  = var.cache.node_type
  nodes                      = var.cache.nodes
}

# The container for the model provider's API key. Its value is put there by a person or a pipeline
# (aws secretsmanager put-secret-value), so the key is never in this repository or in the state.
resource "aws_secretsmanager_secret" "model_api_key" {
  name                    = "${local.name}/model-api-key"
  description             = "API key of the model provider for ${local.name}"
  recovery_window_in_days = var.environment == "prod" ? 30 : 7
}

data "aws_caller_identity" "this" {}

# The service's pods connect to PostgreSQL as the database user "api" with an IAM token instead of a password.
# The user has to exist in the database with the rds_iam role (CREATE USER api; GRANT rds_iam TO api;).
module "api_identity" {
  source = "../../modules/workload-identity"

  name            = "${local.name}-api"
  cluster_name    = module.eks.cluster_name
  namespace       = "secop-analyst"
  service_account = "api"
  statements = [{
    sid       = "ConnectAsApi"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${var.region}:${data.aws_caller_identity.this.account_id}:dbuser:${module.postgres.resource_id}/api"]
  }]
}

# External Secrets Operator copies the secrets into Kubernetes secrets of the service's namespace, so the
# service's own pods need no access to Secrets Manager. It may read these two secrets and nothing else.
module "external_secrets_identity" {
  source = "../../modules/workload-identity"

  name            = "${local.name}-external-secrets"
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  statements = [{
    sid       = "ReadTheServiceSecrets"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [module.postgres.master_secret_arn, aws_secretsmanager_secret.model_api_key.arn]
  }]
}

# The AWS Load Balancer Controller turns Ingress and Service objects into load balancers in the public subnets
# (tagged for it in modules/network). Its policy is the one its maintainers publish for v3.6.0:
# policies/load-balancer-controller.json, downloaded unchanged from the project's docs/install/iam_policy.json.
module "load_balancer_controller_identity" {
  source = "../../modules/workload-identity"

  name               = "${local.name}-load-balancer-controller"
  cluster_name       = module.eks.cluster_name
  namespace          = "kube-system"
  service_account    = "aws-load-balancer-controller"
  vendor_policy_json = file("${path.module}/policies/load-balancer-controller.json")
}

# Cluster Autoscaler grows and shrinks the node group with the pods that wait. EKS tags the node group's Auto
# Scaling group with k8s.io/cluster-autoscaler/<cluster> = owned; the actions that change capacity are allowed
# only on groups with that tag, so this cluster's autoscaler cannot resize anything else in the account.
module "cluster_autoscaler_identity" {
  source = "../../modules/workload-identity"

  name            = "${local.name}-cluster-autoscaler"
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "cluster-autoscaler"
  vendor_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadGroupsAndInstanceTypes"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup",
        ]
        Resource = "*" # describe calls do not take resource ARNs
      },
      {
        Sid      = "ResizeOnlyThisClustersGroups"
        Effect   = "Allow"
        Action   = ["autoscaling:SetDesiredCapacity", "autoscaling:TerminateInstanceInAutoScalingGroup"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:ResourceTag/k8s.io/cluster-autoscaler/${module.eks.cluster_name}" = "owned" }
        }
      },
    ]
  })
}

# Where the service's image lives. The nodes already have pull-only access to ECR (modules/eks).
# The nodes are Graviton (t4g, m7g): the image has to be built for linux/arm64, or for both architectures.
resource "aws_ecr_repository" "api" {
  name                 = "${local.name}/api"
  image_tag_mutability = "IMMUTABLE" # a tag always means the same image, so a rollback goes back to what ran
  force_delete         = var.environment != "prod"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

# Untagged layers and old builds are deleted; the newest images stay for rollbacks.
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Untagged images after a day"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 1 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the newest ${var.images_to_keep}"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.images_to_keep }
        action       = { type = "expire" }
      },
    ]
  })
}

# What the environment costs, checked against a monthly amount. EKS's control plane and every NAT gateway are
# billed by the hour whether anything runs or not, so an environment left up is the usual surprise.
# The filter uses the Environment tag that the providers in envs/ put on everything: it has to be activated
# once as a cost allocation tag in the billing console, or the budget sees nothing.
resource "aws_budgets_budget" "monthly" {
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Environment$%s", var.environment)]
  }

  # Warned twice: when what was spent passes 80 %, and when the forecast says the month will pass the whole amount.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_emails
  }
}

# Alarms on the managed services, sent to the same people as the budget. Each fires after ten minutes past its
# threshold. CloudWatch bills each alarm monthly once applied.
# The topic's key has to be a customer-managed one: CloudWatch cannot publish to a topic encrypted with the
# AWS-managed key for SNS, because that key's policy cannot be changed to let it in.
resource "aws_kms_key" "alerts" {
  description             = "Encrypts the alerts topic of ${local.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "TheAccountAdministersTheKey"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.this.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchPublishesAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
      },
    ]
  })
}

resource "aws_sns_topic" "alerts" {
  name              = "${local.name}-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn
}

# Each address gets a confirmation email from AWS and receives nothing until it is accepted.
resource "aws_sns_topic_subscription" "alerts" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

locals {
  database_alarms = {
    cpu     = { name = "CPU above 80 %", metric = "CPUUtilization", comparison = "GreaterThanThreshold", threshold = 80 }
    storage = { name = "less than ${var.database.free_storage_alarm_gb} GB of storage free", metric = "FreeStorageSpace", comparison = "LessThanThreshold", threshold = var.database.free_storage_alarm_gb * 1024 * 1024 * 1024 }
    memory  = { name = "less than 128 MB of memory free", metric = "FreeableMemory", comparison = "LessThanThreshold", threshold = 128 * 1024 * 1024 }
  }
  cache_alarms = merge([for node in module.redis.member_clusters : {
    "${node}-memory" = { node = node, name = "${node}: memory above 80 %", metric = "DatabaseMemoryUsagePercentage" }
    "${node}-cpu"    = { node = node, name = "${node}: engine CPU above 80 %", metric = "EngineCPUUtilization" }
  }]...)
}

resource "aws_cloudwatch_metric_alarm" "database" {
  for_each            = local.database_alarms
  alarm_name          = "${local.name}-database-${each.key}"
  alarm_description   = "PostgreSQL of ${local.name}: ${each.value.name}"
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBInstanceIdentifier = module.postgres.identifier }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 10
  comparison_operator = each.value.comparison
  threshold           = each.value.threshold
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "cache" {
  for_each            = local.cache_alarms
  alarm_name          = "${local.name}-cache-${each.key}"
  alarm_description   = "Cache of ${local.name}, ${each.value.name}"
  namespace           = "AWS/ElastiCache"
  metric_name         = each.value.metric
  dimensions          = { CacheClusterId = each.value.node }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 10
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
