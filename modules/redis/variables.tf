variable "name" {
  description = "Identifier of the replication group and prefix of what belongs to it."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cache lives in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the cache nodes. Use the ones with no route to the internet."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups that may connect, as a map from a name used in the rule's description to the group's ID."
  type        = map(string)
}

variable "engine" {
  description = "valkey or redis."
  type        = string
  default     = "valkey"

  validation {
    condition     = contains(["valkey", "redis"], var.engine)
    error_message = "engine is valkey or redis."
  }
}

variable "engine_version" {
  description = "Engine version, major.minor."
  type        = string
  default     = "8.0"
}

variable "node_type" {
  description = "ElastiCache node type."
  type        = string
  default     = "cache.t4g.micro"
}

variable "nodes" {
  description = "Number of nodes: one primary and the rest replicas. With two or more, a replica in another zone takes over if the primary fails."
  type        = number
  default     = 2

  validation {
    condition     = var.nodes >= 1 && var.nodes <= 6
    error_message = "nodes is between 1 and 6."
  }
}

variable "eviction_policy" {
  description = "maxmemory-policy. volatile-ttl drops the keys closest to expiring, which suits data that is written with a TTL."
  type        = string
  default     = "volatile-ttl"
}

variable "kms_key_arn" {
  description = "KMS key for encryption at rest. Null uses the service's own key. The data is encrypted either way."
  type        = string
  default     = null
}

variable "snapshot_retention_days" {
  description = "Days of daily snapshots. Zero takes none, which is right when everything in the cache can be rebuilt or is meant to expire."
  type        = number
  default     = 0
}
