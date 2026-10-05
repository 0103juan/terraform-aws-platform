# A PostgreSQL instance on RDS that only the security groups it is given can reach.
# pgvector ships with RDS for PostgreSQL: the application enables it with CREATE EXTENSION vector.

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.name}-postgres"
  description = "PostgreSQL ${var.name}: reachable only from the groups listed as rules"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-postgres" }
}

# One rule per client, each a reference to a security group and never an address range: access follows the
# workload, not wherever its address happens to be.
resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each                     = var.allowed_security_group_ids
  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL from ${each.key}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-"
  family      = "postgres${split(".", var.engine_version)[0]}"

  parameter {
    name  = "rds.force_ssl" # a client that does not use TLS is refused
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement" # milliseconds: slow statements end up in the log
    value = tostring(var.slow_query_ms)
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class
  db_name        = var.database_name

  # The master password is created and rotated by RDS in Secrets Manager. It never passes through Terraform,
  # so it is not in the state file either.
  username                            = var.master_username
  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = var.multi_az
  parameter_group_name   = aws_db_parameter_group.this.name

  backup_retention_period   = var.backup_retention_days
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-final"

  auto_minor_version_upgrade      = true
  apply_immediately               = false # changes that restart the instance wait for the maintenance window
  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
}
