variable "project_id" {
  description = "Project of the cluster and of the service account."
  type        = string
}

variable "name" {
  description = "Account ID of the Google service account: 6 to 30 lowercase letters, digits or hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.name))
    error_message = "name is 6 to 30 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "namespace" {
  description = "Kubernetes namespace of the service account."
  type        = string
}

variable "service_account" {
  description = "Kubernetes service account whose pods act as the Google service account."
  type        = string
}

variable "project_roles" {
  description = "Roles on the whole project. Prefer grants on single resources, made with the email this module returns."
  type        = set(string)
  default     = []

  validation {
    condition     = length(setintersection(var.project_roles, ["roles/owner", "roles/editor", "roles/viewer"])) == 0
    error_message = "A workload gets named roles: the basic roles Owner, Editor and Viewer are refused."
  }
}
