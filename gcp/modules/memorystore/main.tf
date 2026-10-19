# Memorystore for Redis with a private address, AUTH and TLS.
# One node (BASIC) has no failover; two (STANDARD_HA) keep a replica in another zone that takes over.

resource "google_redis_instance" "this" {
  project            = var.project_id
  name               = var.name
  region             = var.region
  tier               = var.high_availability ? "STANDARD_HA" : "BASIC"
  memory_size_gb     = var.memory_size_gb
  redis_version      = var.redis_version
  authorized_network = var.network_id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"
  labels             = var.labels

  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"

  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 4
        minutes = 0
      }
    }
  }
}
