# Everything one environment of the agent service needs on Google Cloud, composed from the modules. An
# environment is this stack with its own values, its own project and its own state (see gcp/envs/).

locals {
  name = "analyst-${var.environment}"

  apis = toset([
    "artifactregistry.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "monitoring.googleapis.com",
    "redis.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "sts.googleapis.com",
  ])
}

data "google_project" "this" {
  project_id = var.project_id
}

# A project starts with most APIs off. They stay on when the stack is destroyed: turning one off breaks
# whatever else in the project uses it.
resource "google_project_service" "this" {
  for_each           = local.apis
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "network" {
  source = "../../modules/network"

  project_id = var.project_id
  name       = local.name
  region     = var.region
  cidr       = var.cidr

  depends_on = [google_project_service.this]
}

module "gke" {
  source = "../../modules/gke"

  project_id          = var.project_id
  name                = local.name
  region              = var.region
  kubernetes_version  = var.kubernetes_version
  network             = module.network.network_id
  subnetwork          = module.network.subnet_id
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  api_allowed_cidrs   = var.api_allowed_cidrs
  admin_members       = var.admin_members
  machine_type        = var.nodes.machine_type
  spot                = var.nodes.spot
  node_count          = { min = var.nodes.min, max = var.nodes.max }
  deletion_protection = var.environment == "prod"
  labels              = { environment = var.environment }
}

module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id            = var.project_id
  name                  = local.name
  region                = var.region
  network_id            = module.network.network_id
  database_name         = "secop"
  iam_service_accounts  = { api = module.api_identity.email }
  tier                  = var.database.tier
  high_availability     = var.database.high_availability
  backup_retention_days = var.database.backup_retention_days
  deletion_protection   = var.database.deletion_protection
  labels                = { environment = var.environment }

  depends_on = [module.network] # the peering with Google's services has to exist first
}

module "memorystore" {
  source = "../../modules/memorystore"

  project_id        = var.project_id
  name              = local.name
  region            = var.region
  network_id        = module.network.network_id
  memory_size_gb    = var.cache.memory_size_gb
  high_availability = var.cache.high_availability
  labels            = { environment = var.environment }

  depends_on = [module.network]
}

# Where the service's image lives. The nodes can pull from it (roles/artifactregistry.reader in modules/gke).
resource "google_artifact_registry_repository" "api" {
  project       = var.project_id
  location      = var.region
  repository_id = local.name
  format        = "DOCKER"
  description   = "Images of ${local.name}"

  docker_config {
    immutable_tags = true # a tag always means the same image, so a rollback goes back to what ran
  }

  # Untagged layers go after a day; the newest images stay for rollbacks.
  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "86400s"
    }
  }
  cleanup_policies {
    id     = "keep-newest"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.images_to_keep
    }
  }

  depends_on = [google_project_service.this]
}

# The container for the model provider's API key. Its value is added by a person or a pipeline
# (gcloud secrets versions add), so the key is never in this repository or in the state.
resource "google_secret_manager_secret" "model_api_key" {
  project   = var.project_id
  secret_id = "${local.name}-model-api-key"
  labels    = { environment = var.environment }

  replication {
    auto {}
  }

  depends_on = [google_project_service.this]
}

# The cache's AUTH password, so that workloads read it from one place. It is in the state either way.
resource "google_secret_manager_secret" "cache_auth" {
  project   = var.project_id
  secret_id = "${local.name}-cache-auth"
  labels    = { environment = var.environment }

  replication {
    auto {}
  }

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_version" "cache_auth" {
  secret      = google_secret_manager_secret.cache_auth.id
  secret_data = module.memorystore.auth_string
}

# The service's pods: they connect to Cloud SQL as their own database user, with no password.
module "api_identity" {
  source = "../../modules/workload-identity"

  project_id      = var.project_id
  name            = "${local.name}-api"
  namespace       = "secop-analyst"
  service_account = "api"
  project_roles   = ["roles/cloudsql.client", "roles/cloudsql.instanceUser"]

  depends_on = [module.gke] # the cluster creates the workload identity pool these bindings name
}

# External Secrets Operator copies the secrets into Kubernetes secrets of the service's namespace, so the
# service's own pods need no access to Secret Manager. It may read these two secrets and nothing else.
module "external_secrets_identity" {
  source = "../../modules/workload-identity"

  project_id      = var.project_id
  name            = "${local.name}-eso"
  namespace       = "external-secrets"
  service_account = "external-secrets"

  depends_on = [module.gke] # the cluster creates the workload identity pool these bindings name
}

resource "google_secret_manager_secret_iam_member" "external_secrets" {
  for_each = {
    model_api_key = google_secret_manager_secret.model_api_key.secret_id
    cache_auth    = google_secret_manager_secret.cache_auth.secret_id
  }
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = module.external_secrets_identity.member
}

resource "google_monitoring_notification_channel" "email" {
  for_each     = toset(var.alert_emails)
  project      = var.project_id
  display_name = "${local.name}: ${each.value}"
  type         = "email"
  labels       = { email_address = each.value }

  depends_on = [google_project_service.this]
}

# What the environment costs, checked against a monthly amount. A GKE cluster bills for its nodes whether
# anything runs or not, so an environment left up is the usual surprise. The filter uses the environment
# label; resources that carry no labels are counted through the project filter.
resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account
  display_name    = "${local.name}-monthly"

  budget_filter {
    projects        = ["projects/${data.google_project.this.number}"]
    calendar_period = "MONTH"
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency # must be the billing account's currency
      units         = tostring(var.monthly_budget)
    }
  }

  # Warned twice: when what was spent passes 80 %, and when the forecast says the month will pass the whole amount.
  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = [for channel in google_monitoring_notification_channel.email : channel.id]
    disable_default_iam_recipients   = false
  }
}

# Alarms on the managed services: each fires after ten minutes above its threshold and emails the same people.
locals {
  database = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${var.project_id}:${module.cloud_sql.instance_name}\""
  alerts = {
    database_cpu    = { name = "Cloud SQL CPU above 80 %", threshold = 0.8, filter = "${local.database} AND metric.type = \"cloudsql.googleapis.com/database/cpu/utilization\"" }
    database_memory = { name = "Cloud SQL memory above 90 %", threshold = 0.9, filter = "${local.database} AND metric.type = \"cloudsql.googleapis.com/database/memory/utilization\"" }
    database_disk   = { name = "Cloud SQL disk above 85 %", threshold = 0.85, filter = "${local.database} AND metric.type = \"cloudsql.googleapis.com/database/disk/utilization\"" }
    cache_memory    = { name = "Memorystore memory above 80 %", threshold = 0.8, filter = "resource.type = \"redis_instance\" AND resource.labels.instance_id = \"${module.memorystore.id}\" AND metric.type = \"redis.googleapis.com/stats/memory/usage_ratio\"" }
  }
}

resource "google_monitoring_alert_policy" "this" {
  for_each              = local.alerts
  project               = var.project_id
  display_name          = "${local.name}: ${each.value.name}"
  combiner              = "OR"
  severity              = "WARNING"
  notification_channels = [for channel in google_monitoring_notification_channel.email : channel.id]

  conditions {
    display_name = each.value.name
    condition_threshold {
      filter          = each.value.filter
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = "600s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
}
