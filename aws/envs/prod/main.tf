# Production: the same stack, sized to lose a zone and keep answering. Three zones with a NAT gateway each,
# on-demand nodes, a database with a standby and deletion protection, a cache with a replica, and a
# Kubernetes API with no public endpoint.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "REPLACE-terraform-state"
    key          = "analyst/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "analyst"
      Environment = "prod"
      ManagedBy   = "terraform"
      Repository  = "terraform-cloud-platform"
    }
  }
}

module "analyst" {
  source = "../../stacks/analyst"

  environment        = "prod"
  region             = "us-east-1"
  cidr               = "10.30.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  kubernetes_version = "1.34"
  admin_role_arns    = var.admin_role_arns
  monthly_budget_usd = 1500
  alert_emails       = var.alert_emails

  nodes    = { instance_types = ["m7g.large"], capacity_type = "ON_DEMAND", min = 3, max = 6 }
  database = { instance_class = "db.m7g.large", multi_az = true, backup_retention_days = 14, deletion_protection = true }
  cache    = { node_type = "cache.m7g.large", nodes = 2 }
}
