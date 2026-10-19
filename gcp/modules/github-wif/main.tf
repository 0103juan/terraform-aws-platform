# A service account that GitHub Actions impersonates with a short-lived token (Workload Identity Federation),
# so that no service account key is stored in a repository's secrets. Two locks, like the AWS module's trust
# policy: the provider accepts only tokens whose subject is listed, and the service account lets only those
# exact subjects impersonate it. A workflow anywhere else on GitHub gets nothing.

locals {
  pool_name = var.create_pool ? google_iam_workload_identity_pool.github[0].name : var.pool_name
}

# One pool can serve many repositories; a second stack in the same project passes the first one's name.
resource "google_iam_workload_identity_pool" "github" {
  count                     = var.create_pool ? 1 : 0
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = var.pool_id
  workload_identity_pool_provider_id = var.name
  display_name                       = var.name

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  attribute_condition = "assertion.sub in ${jsonencode(var.subjects)}"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  depends_on = [google_iam_workload_identity_pool.github]
}

resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = var.name
  display_name = "GitHub Actions: ${var.name}"
}

resource "google_service_account_iam_member" "github" {
  for_each           = toset(var.subjects)
  service_account_id = google_service_account.this.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${local.pool_name}/subject/${each.value}"
}

resource "google_project_iam_member" "this" {
  for_each = var.project_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.this.email}"
}
