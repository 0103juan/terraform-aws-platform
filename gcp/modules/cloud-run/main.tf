# A Cloud Run service with its own service account, for workloads that do not need a cluster.
#   - It runs as a service account of its own, which can read only the secrets it is given.
#   - Secrets reach it as environment variables read from Secret Manager at start, not as values in the state.
#   - Ingress is internal unless said otherwise, and nobody may invoke it unless listed.
#   - Optional Direct VPC egress, so it reaches Cloud SQL and Memorystore on their private addresses.

resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = var.name
  display_name = "Cloud Run service ${var.name}"
}

resource "google_secret_manager_secret_iam_member" "this" {
  for_each  = var.secrets
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.this.email}"
}

resource "google_cloud_run_v2_service" "this" {
  project             = var.project_id
  name                = var.name
  location            = var.region
  ingress             = var.ingress
  deletion_protection = var.deletion_protection
  labels              = var.labels

  template {
    service_account                  = google_service_account.this.email
    max_instance_request_concurrency = var.concurrency
    timeout                          = "${var.timeout_seconds}s"

    scaling {
      min_instance_count = var.instances.min
      max_instance_count = var.instances.max
    }

    containers {
      image = var.image

      ports {
        container_port = var.port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle = var.instances.min == 0 # with instances kept warm, CPU stays allocated for background work
      }

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        http_get {
          path = var.health_path
        }
      }
    }

    dynamic "vpc_access" {
      for_each = var.vpc == null ? [] : [var.vpc]
      content {
        egress = "PRIVATE_RANGES_ONLY"
        network_interfaces {
          network    = vpc_access.value.network
          subnetwork = vpc_access.value.subnetwork
        }
      }
    }
  }

  # The secrets have to be readable before the first revision starts.
  depends_on = [google_secret_manager_secret_iam_member.this]
}

resource "google_cloud_run_v2_service_iam_member" "invokers" {
  for_each = var.invokers
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value
}
