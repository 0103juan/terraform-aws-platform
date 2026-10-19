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

output "member_clusters" {
  description = "IDs of the cache's nodes (<id>-001, <id>-002...), as CloudWatch's CacheClusterId dimension names them. Built from the node count so they are known at plan."
  value       = [for n in range(var.nodes) : format("%s-%03d", var.name, n + 1)]
}
