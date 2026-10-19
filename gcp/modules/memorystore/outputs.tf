output "id" {
  description = "ID of the instance, as Cloud Monitoring labels it."
  value       = google_redis_instance.this.id
}

output "url" {
  description = "Connection URL without the password. The scheme is rediss because the instance only accepts TLS."
  value       = "rediss://${google_redis_instance.this.host}:${google_redis_instance.this.port}/0"
}

output "auth_string" {
  description = "The AUTH password. It is in the state, as every attribute is: keep the state bucket private."
  value       = google_redis_instance.this.auth_string
  sensitive   = true
}

output "server_ca_certs" {
  description = "Certificates that sign the instance's TLS certificate, for clients to trust."
  value       = google_redis_instance.this.server_ca_certs
  sensitive   = true
}
