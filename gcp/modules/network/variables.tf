variable "project_id" {
  description = "Project the network belongs to."
  type        = string
}

variable "name" {
  description = "Prefix for every resource name, for example \"analyst-dev\"."
  type        = string
}

variable "region" {
  description = "Region of the subnet, the router and the NAT."
  type        = string
}

variable "cidr" {
  description = "IPv4 /16 the environment's ranges are cut from: workloads, pods, services and Google's managed services."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr, 0)) && endswith(var.cidr, "/16")
    error_message = "cidr must be a valid IPv4 /16, for example 10.30.0.0/16."
  }
}

variable "flow_log_sampling" {
  description = "Share of flows recorded, between 0 and 1. Flow logs are billed by volume."
  type        = number
  default     = 0.5

  validation {
    condition     = var.flow_log_sampling > 0 && var.flow_log_sampling <= 1
    error_message = "flow_log_sampling is above 0 and at most 1: turning flow logs off is not offered."
  }
}
