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
