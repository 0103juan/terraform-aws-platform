mock_provider "aws" {}

variables {
  name                       = "test"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-a", "subnet-b"]
  allowed_security_group_ids = { workloads = "sg-workloads" }
}

run "encrypted_and_with_a_replica_by_default" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.at_rest_encryption_enabled == "true" && aws_elasticache_replication_group.this.transit_encryption_enabled
    error_message = "The cache is encrypted at rest and only accepts TLS."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.automatic_failover_enabled && aws_elasticache_replication_group.this.multi_az_enabled
    error_message = "Two nodes means a replica in another zone that takes over."
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.family == "valkey8"
    error_message = "The parameter group family is the engine and its major version."
  }
}

run "a_single_node_has_no_failover_to_configure" {
  command = plan

  variables {
    nodes = 1
  }

  assert {
    condition     = !aws_elasticache_replication_group.this.automatic_failover_enabled && !aws_elasticache_replication_group.this.multi_az_enabled
    error_message = "Failover needs a second node; asking for it with one is an API error."
  }
}

run "an_unknown_engine_is_refused" {
  command = plan

  variables {
    engine = "memcached"
  }

  expect_failures = [var.engine]
}
