# The modules have their own tests. This one checks that they fit together: that the stack plans in the
# shape of each environment, which catches a renamed output, a wrong type or a missing argument.
mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789012"
    }
  }
}

variables {
  project_id         = "analyst-test"
  region             = "us-central1"
  cidr               = "10.30.0.0/16"
  kubernetes_version = "1.34"
  billing_account    = "012345-6789AB-CDEF01"
  monthly_budget     = 150
  alert_emails       = ["platform@example.com"]
}

run "plans_in_the_shape_of_dev" {
  command = plan

  variables {
    environment = "dev"
    nodes       = { machine_type = "e2-standard-2", spot = true, min = 1, max = 2 }
    database    = { tier = "db-custom-1-3840", high_availability = false, backup_retention_days = 1, deletion_protection = false }
    cache       = { memory_size_gb = 1, high_availability = false }
  }

  assert {
    condition     = google_artifact_registry_repository.api.docker_config[0].immutable_tags
    error_message = "A tag always names the same image."
  }

  assert {
    condition     = tolist(google_billing_budget.monthly.budget_filter[0].projects) == tolist(["projects/123456789012"])
    error_message = "The budget counts this environment's project only."
  }

  assert {
    condition     = length(google_monitoring_alert_policy.this) == 4 && length(google_secret_manager_secret_iam_member.external_secrets) == 2
    error_message = "Four alarms, and External Secrets reads exactly the two secrets."
  }

  assert {
    condition     = strcontains(google_monitoring_alert_policy.this["database_cpu"].conditions[0].condition_threshold[0].filter, "database_id = \"analyst-test:analyst-dev\"")
    error_message = "The database alarms watch this instance, named PROJECT:INSTANCE."
  }
}

run "plans_in_the_shape_of_prod" {
  command = plan

  variables {
    environment = "prod"
    nodes       = { machine_type = "e2-standard-4", spot = false, min = 3, max = 6 }
    database    = { tier = "db-custom-2-7680", high_availability = true, backup_retention_days = 14, deletion_protection = true }
    cache       = { memory_size_gb = 2, high_availability = true }
  }

  assert {
    condition     = google_billing_budget.monthly.display_name == "analyst-prod-monthly"
    error_message = "Names carry the environment."
  }
}

run "an_alarm_nobody_hears_about_is_refused" {
  command = plan

  variables {
    environment  = "dev"
    nodes        = { machine_type = "e2-standard-2", spot = true, min = 1, max = 2 }
    database     = { tier = "db-custom-1-3840", high_availability = false, backup_retention_days = 1, deletion_protection = false }
    cache        = { memory_size_gb = 1, high_availability = false }
    alert_emails = []
  }

  expect_failures = [var.alert_emails]
}

run "an_unknown_environment_is_refused" {
  command = plan

  variables {
    environment = "sandbox"
    nodes       = { machine_type = "e2-standard-2", spot = true, min = 1, max = 2 }
    database    = { tier = "db-custom-1-3840", high_availability = false, backup_retention_days = 1, deletion_protection = false }
    cache       = { memory_size_gb = 1, high_availability = false }
  }

  expect_failures = [var.environment]
}
