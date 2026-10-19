variable "project_id" {
  description = "Project of the cluster."
  type        = string
}

variable "name" {
  description = "Name of the cluster and prefix of what belongs to it. At most 24 characters, because the nodes' service account adds \"-nodes\" to it."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,23}$", var.name))
    error_message = "name is 5 to 24 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Region of the cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Minimum Kubernetes minor version. The release channel upgrades from there."
  type        = string

  validation {
    condition     = can(regex("^1\\.\\d{2}$", var.kubernetes_version))
    error_message = "kubernetes_version is a minor version such as 1.34."
  }
}

variable "release_channel" {
  description = "GKE release channel: how soon new versions arrive."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel is RAPID, REGULAR or STABLE."
  }
}

variable "network" {
  description = "VPC of the cluster."
  type        = string
}

variable "subnetwork" {
  description = "Subnet of the nodes. It must carry the pods and services secondary ranges."
  type        = string
}

variable "pods_range_name" {
  description = "Secondary range of the subnet for pod addresses."
  type        = string
}

variable "services_range_name" {
  description = "Secondary range of the subnet for service addresses."
  type        = string
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

variable "admin_members" {
  description = "IAM members that administer the cluster, such as \"group:platform@example.com\". Project owners have access too."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for member in var.admin_members : !contains(["allUsers", "allAuthenticatedUsers"], member)])
    error_message = "Administrators are named: allUsers and allAuthenticatedUsers are refused."
  }
}

variable "machine_type" {
  description = "Machine type of the nodes."
  type        = string
  default     = "e2-standard-2"
}

variable "spot" {
  description = "Run the nodes on Spot VMs: much cheaper, and Google may take them back at any time."
  type        = bool
  default     = false
}

variable "disk_size_gb" {
  description = "Boot disk of each node."
  type        = number
  default     = 50
}

variable "node_count" {
  description = "Smallest and largest number of nodes, across all zones."
  type = object({
    min = number
    max = number
  })
  default = { min = 1, max = 3 }

  validation {
    condition     = var.node_count.min >= 1 && var.node_count.max >= var.node_count.min
    error_message = "node_count needs min >= 1 and max >= min."
  }
}

variable "deletion_protection" {
  description = "Refuse to delete the cluster until this is set to false in a change of its own."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels of the cluster and its nodes. The billing export and the budget can filter by them."
  type        = map(string)
  default     = {}
}
