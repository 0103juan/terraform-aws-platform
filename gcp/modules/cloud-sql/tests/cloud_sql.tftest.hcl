mock_provider "google" {}

variables {
  project_id           = "test-project"
  name                 = "test-db"
  region               = "us-central1"
  network_id           = "projects/test-project/global/networks/test"
  database_name        = "app"
  iam_service_accounts = { api = "api@test-project.iam.gserviceaccount.com" }
}

run "safe_by_default" {
  command = plan

  assert {
    condition     = !google_sql_database_instance.this.settings[0].ip_configuration[0].ipv4_enabled && google_sql_database_instance.this.settings[0].ip_configuration[0].ssl_mode == "ENCRYPTED_ONLY"
    error_message = "No public address, and connections without TLS are refused."
  }

  assert {
    condition     = google_sql_database_instance.this.deletion_protection && google_sql_database_instance.this.settings[0].deletion_protection_enabled && google_sql_database_instance.this.settings[0].availability_type == "REGIONAL"
    error_message = "Protected against deletion in Terraform and in the API, with a standby."
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].backup_configuration[0].enabled && google_sql_database_instance.this.settings[0].backup_configuration[0].point_in_time_recovery_enabled
    error_message = "Backups and point-in-time recovery are on."
  }
}

run "workloads_log_in_with_iam_not_a_password" {
  command = plan

  assert {
    condition     = google_sql_user.iam["api"].name == "api@test-project.iam" && google_sql_user.iam["api"].type == "CLOUD_IAM_SERVICE_ACCOUNT"
    error_message = "The database user is the service account, named the way Cloud SQL expects."
  }

  assert {
    condition     = google_sql_user.iam["api"].password == null
    error_message = "No password is set from Terraform."
  }

  assert {
    condition     = one([for flag in google_sql_database_instance.this.settings[0].database_flags : flag.value if flag.name == "cloudsql.iam_authentication"]) == "on"
    error_message = "IAM authentication is enabled on the instance."
  }
}

run "backups_cannot_be_turned_off" {
  command = plan

  variables {
    backup_retention_days = 0
  }

  expect_failures = [var.backup_retention_days]
}

run "a_user_that_is_not_a_service_account_is_refused" {
  command = plan

  variables {
    iam_service_accounts = { someone = "someone@example.com" }
  }

  expect_failures = [var.iam_service_accounts]
}
