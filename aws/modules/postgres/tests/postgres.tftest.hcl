mock_provider "aws" {}

variables {
  name                       = "test"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-a", "subnet-b"]
  database_name              = "app"
  allowed_security_group_ids = { workloads = "sg-workloads", jobs = "sg-jobs" }
}

run "safe_by_default" {
  command = plan

  assert {
    condition     = aws_db_instance.this.storage_encrypted && !aws_db_instance.this.publicly_accessible
    error_message = "The instance is encrypted and has no public address."
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password && aws_db_instance.this.password == null
    error_message = "The master password is managed by RDS and never set from Terraform."
  }

  assert {
    condition     = aws_db_instance.this.deletion_protection && !aws_db_instance.this.skip_final_snapshot && aws_db_instance.this.multi_az
    error_message = "Deleting takes a deliberate change, leaves a final snapshot, and there is a standby."
  }

  assert {
    condition     = one([for parameter in aws_db_parameter_group.this.parameter : parameter.value if parameter.name == "rds.force_ssl"]) == "1"
    error_message = "Connections without TLS are refused."
  }
}

run "reachable_only_from_the_groups_given" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.clients) == 2
    error_message = "One ingress rule per client group."
  }

  assert {
    condition     = alltrue([for rule in aws_vpc_security_group_ingress_rule.clients : rule.cidr_ipv4 == null && rule.from_port == 5432])
    error_message = "Rules reference security groups, never address ranges."
  }
}

run "the_parameter_family_follows_the_major_version" {
  command = plan

  variables {
    engine_version = "16.4"
  }

  assert {
    condition     = aws_db_parameter_group.this.family == "postgres16"
    error_message = "The parameter group family is the major version."
  }
}

run "backups_cannot_be_turned_off" {
  command = plan

  variables {
    backup_retention_days = 0
  }

  expect_failures = [var.backup_retention_days]
}

run "one_subnet_is_refused" {
  command = plan

  variables {
    subnet_ids = ["subnet-a"]
  }

  expect_failures = [var.subnet_ids]
}
