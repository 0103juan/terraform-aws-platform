output "email" {
  description = "Email of the Google service account. Annotate the Kubernetes service account with it: iam.gke.io/gcp-service-account."
  value       = google_service_account.this.email
}

output "member" {
  description = "The service account as an IAM member, for grants on single resources."
  value       = "serviceAccount:${google_service_account.this.email}"
}
