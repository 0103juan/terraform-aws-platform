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

# The service's pods, and only they, can read the two secrets they need.
module "api_identity" {
  source = "../../modules/workload-identity"

  name            = "${local.name}-api"
  cluster_name    = module.eks.cluster_name
  namespace       = "secop-analyst"
  service_account = "api"
  statements = [{
    sid       = "ReadItsSecrets"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [module.postgres.master_secret_arn, aws_secretsmanager_secret.model_api_key.arn]
  }]
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
    subscriber_email_addresses = var.budget_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_emails
  }
}
