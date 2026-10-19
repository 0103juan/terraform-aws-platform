variable "environment" {
  description = "Name of the environment. Part of every resource name."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment is dev, staging or prod."
  }
}

variable "region" {
  description = "AWS region. Must be the provider's."
  type        = string
}

variable "cidr" {
  description = "IPv4 /16 of the environment's VPC. Give each environment its own, so that they can be peered later."
  type        = string
}

variable "availability_zones" {
  description = "Zones the environment spreads over."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "One NAT gateway for the whole VPC instead of one per zone."
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "Kubernetes minor version of the cluster."
  type        = string
}

variable "api_allowed_cidrs" {
  description = "Address ranges that may reach the Kubernetes API from the internet. Empty makes it private."
  type        = list(string)
  default     = []
}

variable "admin_role_arns" {
  description = "IAM roles that administer the cluster, as a map from a name to the role's ARN."
  type        = map(string)
}

variable "nodes" {
  description = "The cluster's node group."
  type = object({
    instance_types = list(string)
    capacity_type  = string
    min            = number
    max            = number
  })
}

variable "database" {
  description = "The PostgreSQL instance."
  type = object({
    instance_class        = string
    multi_az              = bool
    backup_retention_days = number
    deletion_protection   = bool
    free_storage_alarm_gb = optional(number, 5)
  })
}

variable "cache" {
  description = "The Redis-compatible cache."
  type = object({
    node_type = string
    nodes     = number
  })
}

variable "images_to_keep" {
  description = "How many images of the service the registry keeps, for rollbacks."
  type        = number
  default     = 20
}

variable "monthly_budget_usd" {
  description = "Monthly cost of the environment, in USD, above which the budget warns."
  type        = number

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd is a positive amount."
  }
}

variable "alert_emails" {
  description = "Who the budget and the alarms warn. At least one address."
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0
    error_message = "alert_emails needs at least one address: an alarm nobody hears about protects nothing."
  }
}
