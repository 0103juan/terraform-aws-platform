variable "name" {
  description = "Identifier of the instance and prefix of what belongs to it."
  type        = string
}

variable "vpc_id" {
  description = "VPC the instance lives in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the instance, in two zones at least. Use the ones with no route to the internet."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS needs subnets in at least two availability zones."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups that may connect, as a map from a name used in the rule's description to the group's ID."
  type        = map(string)
}

variable "engine_version" {
  description = "PostgreSQL version, major or major.minor."
  type        = string
  default     = "17"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "database_name" {
  description = "Database created with the instance."
  type        = string
}

variable "master_username" {
  description = "Name of the master user. Its password is managed by RDS in Secrets Manager."
  type        = string
  default     = "postgres"
}

variable "allocated_storage_gb" {
  description = "Storage the instance starts with."
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Ceiling of storage autoscaling."
  type        = number
  default     = 100
}

variable "kms_key_arn" {
  description = "KMS key for storage encryption. Null uses the account's key for RDS. Storage is encrypted either way."
  type        = string
  default     = null
}

variable "multi_az" {
  description = "Keep a standby in another zone and fail over to it."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Days of automated backups, which is also how far back a point-in-time restore can go."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backups cannot be turned off here: give between 1 and 35 days."
  }
}

variable "deletion_protection" {
  description = "Refuse to delete the instance until this is set to false in a change of its own."
  type        = bool
  default     = true
}

variable "slow_query_ms" {
  description = "Statements slower than this many milliseconds are logged."
  type        = number
  default     = 1000
}
