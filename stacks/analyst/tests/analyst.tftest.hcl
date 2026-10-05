# The modules have their own tests. This one checks that they fit together: that the stack plans in the
# shape of each environment, which catches a renamed output, a wrong type or a missing argument.
mock_provider "aws" {}

variables {
  region             = "us-east-1"
  cidr               = "10.20.0.0/16"
  kubernetes_version = "1.34"
  admin_role_arns    = { platform = "arn:aws:iam::111111111111:role/platform-admin" }
}

run "plans_in_the_shape_of_dev" {
  command = plan

  variables {
    environment        = "dev"
    availability_zones = ["us-east-1a", "us-east-1b"]
    single_nat_gateway = true
    nodes              = { instance_types = ["t4g.medium"], capacity_type = "SPOT", min = 1, max = 2 }
    database           = { instance_class = "db.t4g.micro", multi_az = false, backup_retention_days = 1, deletion_protection = false }
    cache              = { node_type = "cache.t4g.micro", nodes = 1 }
  }

  assert {
    condition     = aws_secretsmanager_secret.model_api_key.name == "analyst-dev/model-api-key" && aws_secretsmanager_secret.model_api_key.recovery_window_in_days == 7
    error_message = "Names carry the environment, and a dev secret can be recovered for a week."
  }
}

run "plans_in_the_shape_of_prod" {
  command = plan

  variables {
    environment        = "prod"
    availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
    nodes              = { instance_types = ["m7g.large"], capacity_type = "ON_DEMAND", min = 3, max = 6 }
    database           = { instance_class = "db.m7g.large", multi_az = true, backup_retention_days = 14, deletion_protection = true }
    cache              = { node_type = "cache.m7g.large", nodes = 2 }
  }

  assert {
    condition     = aws_secretsmanager_secret.model_api_key.recovery_window_in_days == 30
    error_message = "A deleted production secret can be recovered for thirty days."
  }
}

run "an_unknown_environment_is_refused" {
  command = plan

  variables {
    environment        = "sandbox"
    availability_zones = ["us-east-1a", "us-east-1b"]
    nodes              = { instance_types = ["t4g.medium"], capacity_type = "SPOT", min = 1, max = 2 }
    database           = { instance_class = "db.t4g.micro", multi_az = false, backup_retention_days = 1, deletion_protection = false }
    cache              = { node_type = "cache.t4g.micro", nodes = 1 }
  }

  expect_failures = [var.environment]
}
