variable "name" {
  description = "Name of the cluster and prefix of what belongs to it."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, for example \"1.34\". Pinned, because an upgrade is a change to review."
  type        = string

  validation {
    condition     = can(regex("^1\\.\\d{2}$", var.kubernetes_version))
    error_message = "kubernetes_version is a minor version such as 1.34."
  }
}

variable "subnet_ids" {
  description = "Private subnets for the control plane's network interfaces and for the nodes, in two zones at least."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS needs subnets in at least two availability zones."
  }
}

variable "api_allowed_cidrs" {
  description = "Address ranges that may reach the Kubernetes API from the internet. Empty makes the API private to the VPC."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.api_allowed_cidrs, "0.0.0.0/0")
    error_message = "The Kubernetes API is not opened to the whole internet: list the ranges that need it."
  }
}

variable "admin_role_arns" {
  description = "IAM roles that administer the cluster, as a map from a name to the role's ARN. Nobody else gets in, not even the identity that creates the cluster."
  type        = map(string)
}

variable "node_instance_types" {
  description = "Instance types the node group may use."
  type        = list(string)
  default     = ["t4g.large"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type is ON_DEMAND or SPOT."
  }
}

variable "node_count" {
  description = "Smallest and largest number of nodes."
  type = object({
    min = number
    max = number
  })
  default = { min = 2, max = 4 }

  validation {
    condition     = var.node_count.min >= 1 && var.node_count.max >= var.node_count.min
    error_message = "node_count needs min >= 1 and max >= min."
  }
}

variable "log_retention_days" {
  description = "Days the control plane's logs are kept."
  type        = number
  default     = 90
}
