output "uri" {
  description = "URL of the service."
  value       = google_cloud_run_v2_service.this.uri
}

output "service_account" {
  description = "Email of the service account the service runs as, for grants on other resources."
  value       = google_service_account.this.email
}
