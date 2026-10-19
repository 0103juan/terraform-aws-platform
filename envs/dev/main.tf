# The development environment: the stack at its cheapest. One NAT gateway, two zones, spot nodes, a database
# without a standby that can be deleted. An outage here costs an afternoon, not customers.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Its own state file: nothing done to dev can touch prod's state. Replace the bucket with the one
  # modules/state-backend created.
  backend "s3" {
    bucket       = "REPLACE-terraform-state"
    key          = "analyst/dev/terraform.tfstate"
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
      Environment = "dev"
      ManagedBy   = "terraform"
      Repository  = "terraform-aws-platform"
    }
  }
}

module "analyst" {
  source = "../../stacks/analyst"

  environment        = "dev"
  region             = "us-east-1"
  cidr               = "10.20.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  single_nat_gateway = true
  kubernetes_version = "1.34"
  api_allowed_cidrs  = var.api_allowed_cidrs
  admin_role_arns    = var.admin_role_arns
  monthly_budget_usd = 150
  budget_emails      = var.budget_emails

  nodes    = { instance_types = ["t4g.medium"], capacity_type = "SPOT", min = 1, max = 2 }
  database = { instance_class = "db.t4g.micro", multi_az = false, backup_retention_days = 1, deletion_protection = false }
  cache    = { node_type = "cache.t4g.micro", nodes = 1 }
}
