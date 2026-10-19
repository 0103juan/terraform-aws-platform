variable "environment" {
  description = "Name of the environment. Part of every resource name."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment is dev, staging or prod."
  }
}

variable "project_id" {
  description = "Project of the environment. One project per environment keeps IAM and quotas apart."
  type        = string
}

variable "region" {
  description = "Region of the environment."
  type        = string
}

variable "cidr" {
  description = "IPv4 /16 the environment's ranges are cut from. Give each environment its own, so that they can be peered later."
  type        = string
}

variable "kubernetes_version" {
  description = "Minimum Kubernetes minor version of the cluster."
  type        = string
}

variable "api_allowed_cidrs" {
  description = "Address ranges that may reach the Kubernetes API from the internet. Empty makes it private."
  type        = list(string)
  default     = []
}

variable "admin_members" {
  description = "IAM members that administer the cluster, such as \"group:platform@example.com\"."
  type        = set(string)
  default     = []
}

variable "nodes" {
  description = "The cluster's node pool."
  type = object({
    machine_type = string
    spot         = bool
    min          = number
    max          = number
  })
}

variable "database" {
  description = "The Cloud SQL instance."
  type = object({
    tier                  = string
    high_availability     = bool
    backup_retention_days = number
    deletion_protection   = bool
  })
}

variable "cache" {
  description = "The Memorystore instance."
  type = object({
    memory_size_gb    = number
    high_availability = bool
  })
}

variable "images_to_keep" {
  description = "How many images of the service the registry keeps, for rollbacks."
  type        = number
  default     = 20
}

variable "billing_account" {
  description = "Billing account the budget is created in (XXXXXX-XXXXXX-XXXXXX)."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", var.billing_account))
    error_message = "billing_account looks like 012345-6789AB-CDEF01."
  }
}

variable "monthly_budget" {
  description = "Monthly cost of the environment, in budget_currency, above which the budget warns."
  type        = number

  validation {
    condition     = var.monthly_budget > 0
    error_message = "monthly_budget is a positive amount."
  }
}

variable "budget_currency" {
  description = "Currency of the billing account, such as USD or COP. A budget in another currency is rejected."
  type        = string
  default     = "USD"
}

variable "alert_emails" {
  description = "Who the budget and the alarms warn. At least one address."
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0
    error_message = "alert_emails needs at least one address: an alarm nobody hears about protects nothing."
  }
}
