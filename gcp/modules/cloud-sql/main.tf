# Cloud SQL for PostgreSQL with a private address only.
#   - No public IP; connections without TLS are refused.
#   - Workloads log in as their service account (IAM database authentication): there is no password to create,
#     store or rotate, so none is in the state. RDS needs a master password in Secrets Manager; this does not.
#   - Backups with point-in-time recovery cannot be turned off.

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = var.name
  region              = var.region
  database_version    = "POSTGRES_${var.engine_version}"
  deletion_protection = var.deletion_protection # Terraform's own guard

  settings {
    tier                        = var.tier
    edition                     = "ENTERPRISE"
    availability_type           = var.high_availability ? "REGIONAL" : "ZONAL" # REGIONAL keeps a standby in another zone
    deletion_protection_enabled = var.deletion_protection                      # the API's guard, which also stops the console
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.max_disk_size_gb
    user_labels                 = var.labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
      transaction_log_retention_days = min(var.backup_retention_days, 7)

      backup_retention_settings {
        retained_backups = var.backup_retention_days
        retention_unit   = "COUNT"
      }
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = tostring(var.slow_query_ms)
    }

    # Who connected and when, lock waits, checkpoints and every temporary file: what an incident review asks for.
    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_temp_files"
      value = "0"
    }

    insights_config {
      query_insights_enabled = true
    }

    # Restarts wait for Sunday 04:00 UTC and for the stable track of updates.
    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }
  }
}

resource "google_sql_database" "this" {
  project  = var.project_id
  name     = var.database_name
  instance = google_sql_database_instance.this.name
}

# One database user per service account that connects. Cloud SQL names the user after the account's email,
# without ".gserviceaccount.com". Keyed by a fixed name: an email made in the same apply is not known at plan.
resource "google_sql_user" "iam" {
  for_each = var.iam_service_accounts
  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = trimsuffix(each.value, ".gserviceaccount.com")
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}
