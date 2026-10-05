output "primary_endpoint" {
  description = "Host name that always points at the primary node."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "url" {
  description = "Connection URL. The scheme is rediss because the cache only accepts TLS."
  value       = "rediss://${aws_elasticache_replication_group.this.primary_endpoint_address}:6379/0"
}

output "security_group_id" {
  description = "Security group of the cache."
  value       = aws_security_group.this.id
}
