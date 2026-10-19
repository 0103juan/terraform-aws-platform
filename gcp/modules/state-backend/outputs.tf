output "bucket" {
  description = "Name to put in the gcs backend block of each environment."
  value       = google_storage_bucket.state.name
}
