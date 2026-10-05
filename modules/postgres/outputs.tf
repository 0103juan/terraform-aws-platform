output "endpoint" {
  description = "Host name of the instance."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port of the instance."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Database created with the instance."
  value       = aws_db_instance.this.db_name
}

output "security_group_id" {
  description = "Security group of the instance."
  value       = aws_security_group.this.id
}

output "master_secret_arn" {
  description = "Secrets Manager secret that holds the master user's password. Grant a workload read access to it instead of copying the password."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
