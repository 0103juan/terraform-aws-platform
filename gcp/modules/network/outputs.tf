output "network_id" {
  description = "ID of the VPC, as Cloud SQL and Memorystore take it."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "Name of the VPC."
  value       = google_compute_network.this.name
}

output "subnet_id" {
  description = "ID of the workloads subnet."
  value       = google_compute_subnetwork.workloads.id
}

output "subnet_name" {
  description = "Name of the workloads subnet."
  value       = google_compute_subnetwork.workloads.name
}

output "pods_range_name" {
  description = "Secondary range for GKE's pods."
  value       = "pods"
}

output "services_range_name" {
  description = "Secondary range for GKE's services."
  value       = "services"
}

output "managed_services_connection" {
  description = "The peering with Google's managed services. Cloud SQL and Memorystore with private addresses need it to exist first."
  value       = google_service_networking_connection.managed_services.id
}
