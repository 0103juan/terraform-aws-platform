variable "project_id" {
  description = "Project of the instance."
  type        = string
}

variable "name" {
  description = "Name of the instance. Cloud SQL does not reuse a name for about a week after deletion."
  type        = string
}

variable "region" {
  description = "Region of the instance."
  type        = string
}

variable "network_id" {
  description = "VPC with Private Service Access the instance takes its address from."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major version."
  type        = number
  default     = 17
}

variable "tier" {
  description = "Machine tier, such as db-custom-1-3840 (1 vCPU, 3.75 GB)."
  type        = string
  default     = "db-custom-1-3840"
}

variable "high_availability" {
  description = "Keep a standby in another zone and fail over to it."
  type        = bool
  default     = true
}

variable "database_name" {
  description = "Database created with the instance."
  type        = string
}

variable "iam_service_accounts" {
  description = "Service accounts that connect as database users with IAM authentication, as a map from a fixed name to the account's email."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for email in values(var.iam_service_accounts) : endswith(email, ".gserviceaccount.com")])
    error_message = "Each entry is a service account email, ending in .gserviceaccount.com."
  }
}

variable "disk_size_gb" {
  description = "Storage the instance starts with."
  type        = number
  default     = 20
}

variable "max_disk_size_gb" {
  description = "Ceiling of storage autoresize."
  type        = number
  default     = 100
}

variable "backup_retention_days" {
  description = "Daily backups kept. Point-in-time recovery reaches back as far as the last seven days of them."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backups cannot be turned off here: keep between 1 and 365."
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

variable "labels" {
  description = "Labels of the instance."
  type        = map(string)
  default     = {}
}
