# The modules have their own tests. This one checks that they fit together: that the stack plans in the
# shape of each environment, which catches a renamed output, a wrong type or a missing argument.
mock_provider "aws" {}

variables {
  region             = "us-east-1"
  cidr               = "10.20.0.0/16"
  kubernetes_version = "1.34"
  admin_role_arns    = { platform = "arn:aws:iam::111111111111:role/platform-admin" }
  monthly_budget_usd = 150
  alert_emails       = ["platform@example.com"]
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

  assert {
    condition     = aws_ecr_repository.api.image_tag_mutability == "IMMUTABLE" && aws_ecr_repository.api.image_scanning_configuration[0].scan_on_push
    error_message = "A tag always names the same image, and every image is scanned when it is pushed."
  }

  assert {
    condition     = contains(one(aws_budgets_budget.monthly.cost_filter).values, "user:Environment$dev")
    error_message = "The budget counts only what carries this environment's tag."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.database) == 3 && keys(aws_cloudwatch_metric_alarm.cache) == ["analyst-dev-001-cpu", "analyst-dev-001-memory"]
    error_message = "Three database alarms, and two per cache node: dev has one node."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.database["storage"].threshold == 5 * 1024 * 1024 * 1024
    error_message = "The storage alarm counts bytes, as the metric does."
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

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cache) == 4
    error_message = "Prod's two cache nodes get two alarms each."
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

run "an_alarm_nobody_hears_about_is_refused" {
  command = plan

  variables {
    environment        = "dev"
    availability_zones = ["us-east-1a", "us-east-1b"]
    nodes              = { instance_types = ["t4g.medium"], capacity_type = "SPOT", min = 1, max = 2 }
    database           = { instance_class = "db.t4g.micro", multi_az = false, backup_retention_days = 1, deletion_protection = false }
    cache              = { node_type = "cache.t4g.micro", nodes = 1 }
    alert_emails       = []
  }

  expect_failures = [var.alert_emails]
}
