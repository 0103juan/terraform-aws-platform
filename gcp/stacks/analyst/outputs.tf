output "cluster_name" {
  description = "Name of the GKE cluster: gcloud container clusters get-credentials <this> --region <region>."
  value       = module.gke.cluster_name
}

output "database_connection_name" {
  description = "Cloud SQL connection name, for the connector or the Auth Proxy."
  value       = module.cloud_sql.connection_name
}

output "database_user" {
  description = "Database user of the service's pods: their service account, logging in with IAM."
  value       = module.cloud_sql.iam_users["api"]
}

output "cache_url" {
  description = "Connection URL of the cache, without the password (secret cache_auth)."
  value       = module.memorystore.url
}

output "image_repository" {
  description = "Where to push the service's image: docker push <this>/api:<tag>."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.api.repository_id}"
}

output "service_accounts" {
  description = "Google service accounts to annotate the Kubernetes service accounts with (iam.gke.io/gcp-service-account)."
  value = {
    "secop-analyst/api"                 = module.api_identity.email
    "external-secrets/external-secrets" = module.external_secrets_identity.email
  }
}

output "secrets" {
  description = "Secret Manager IDs that the ExternalSecret resources name."
  value = {
    model_api_key = google_secret_manager_secret.model_api_key.secret_id
    cache_auth    = google_secret_manager_secret.cache_auth.secret_id
  }
}
