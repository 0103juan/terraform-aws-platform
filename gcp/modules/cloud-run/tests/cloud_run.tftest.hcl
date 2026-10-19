mock_provider "google" {}

variables {
  project_id = "test-project"
  name       = "test-service"
  region     = "us-central1"
  image      = "us-central1-docker.pkg.dev/test-project/apps/api@sha256:0000000000000000000000000000000000000000000000000000000000000000"
  secrets    = { DATABASE_PASSWORD = "db-password", MODEL_API_KEY = "model-api-key" }
}

run "private_unless_said_otherwise" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.this.ingress == "INGRESS_TRAFFIC_INTERNAL_ONLY" && length(google_cloud_run_v2_service_iam_member.invokers) == 0
    error_message = "Internal ingress and no invokers by default."
  }
}

run "secrets_are_references_not_values" {
  command = plan

  assert {
    condition = alltrue([
      for env in google_cloud_run_v2_service.this.template[0].containers[0].env :
      env.value_source[0].secret_key_ref[0].secret == var.secrets[env.name] if length(env.value_source) > 0
    ]) && length(google_secret_manager_secret_iam_member.this) == 2
    error_message = "Each secret is read from Secret Manager by reference, and the service account can read exactly those."
  }
}

run "more_minimum_than_maximum_instances_is_refused" {
  command = plan

  variables {
    instances = { min = 3, max = 2 }
  }

  expect_failures = [var.instances]
}
