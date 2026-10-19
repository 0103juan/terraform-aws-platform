# A Redis-compatible cache on ElastiCache, encrypted at rest and in transit, reachable only from the security
# groups it is given. Valkey by default: the same protocol and commands as Redis at a lower price.

resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.name}-cache"
  description = "Cache ${var.name}: reachable only from the groups listed as rules"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-cache" }
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each                     = var.allowed_security_group_ids
  security_group_id            = aws_security_group.this.id
  description                  = "Cache from ${each.key}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
}

resource "aws_elasticache_parameter_group" "this" {
  name   = var.name
  family = "${var.engine}${split(".", var.engine_version)[0]}"

  parameter {
    name  = "maxmemory-policy" # what goes first when memory runs out
    value = var.eviction_policy
  }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.name
  description          = "Cache for ${var.name}"
  engine               = var.engine
  engine_version       = var.engine_version
  node_type            = var.node_type
  parameter_group_name = aws_elasticache_parameter_group.this.name
  port                 = 6379

  # Two nodes or more: a replica in another zone that takes over. One node: no failover to configure.
  num_cache_clusters         = var.nodes
  automatic_failover_enabled = var.nodes > 1
  multi_az_enabled           = var.nodes > 1

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  transit_encryption_enabled = true

  snapshot_retention_limit   = var.snapshot_retention_days
  auto_minor_version_upgrade = true
  apply_immediately          = false
}
