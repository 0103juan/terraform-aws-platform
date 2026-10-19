# Google permissions for one Kubernetes service account, through GKE Workload Identity.
# The pods that run as that service account act as this Google service account and no other pod does: the
# alternative, giving the permissions to the nodes' service account, gives them to everything on the node.
# Project-wide roles go in project_roles; grants on one resource (a secret, a bucket) are made by the caller
# with the email this module returns, which is the narrower choice.

resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = var.name
  display_name = "Workload ${var.namespace}/${var.service_account}"
}

resource "google_service_account_iam_member" "workload" {
  service_account_id = google_service_account.this.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.service_account}]"
}

resource "google_project_iam_member" "this" {
  for_each = var.project_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.this.email}"
}
