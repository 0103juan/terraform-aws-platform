mock_provider "google" {}

variables {
  project_id      = "test-project"
  name            = "analyst-dev-api"
  namespace       = "secop-analyst"
  service_account = "api"
  project_roles   = ["roles/cloudsql.client"]
}

run "bound_to_one_kubernetes_service_account" {
  command = plan

  assert {
    condition     = google_service_account_iam_member.workload.member == "serviceAccount:test-project.svc.id.goog[secop-analyst/api]"
    error_message = "Only pods running as secop-analyst/api act as this service account."
  }

  assert {
    condition     = google_service_account_iam_member.workload.role == "roles/iam.workloadIdentityUser"
    error_message = "The binding is Workload Identity's, not a broader role."
  }
}

run "basic_roles_are_refused" {
  command = plan

  variables {
    project_roles = ["roles/editor"]
  }

  expect_failures = [var.project_roles]
}
