output "cluster_name" {
  description = "Name of the cluster: gcloud container clusters get-credentials <this> --region <region>."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "ID of the cluster."
  value       = google_container_cluster.this.id
}

output "workload_pool" {
  description = "Workload Identity pool of the cluster, used to name Kubernetes service accounts in IAM."
  value       = "${var.project_id}.svc.id.goog"
}

output "nodes_service_account" {
  description = "Service account the nodes run as."
  value       = google_service_account.nodes.email
}
