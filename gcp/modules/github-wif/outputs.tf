output "service_account" {
  description = "Email to put in google-github-actions/auth as service_account."
  value       = google_service_account.this.email
}

output "workload_identity_provider" {
  description = "Provider name to put in google-github-actions/auth as workload_identity_provider."
  value       = google_iam_workload_identity_pool_provider.github.name
}
