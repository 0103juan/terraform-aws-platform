output "connection_name" {
  description = "PROJECT:REGION:INSTANCE, what the Cloud SQL connectors and the Auth Proxy take."
  value       = google_sql_database_instance.this.connection_name
}

output "instance_name" {
  description = "Name of the instance."
  value       = google_sql_database_instance.this.name
}

output "private_ip" {
  description = "Private address of the instance."
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_name" {
  description = "Database created with the instance."
  value       = google_sql_database.this.name
}

output "iam_users" {
  description = "Database user name of each service account, keyed like iam_service_accounts."
  value       = { for key, user in google_sql_user.iam : key => user.name }
}
