variable "project_id" {
  description = "Project of the pool and the service account."
  type        = string
}

variable "name" {
  description = "Account ID of the service account and ID of the pool provider: 6 to 30 lowercase letters, digits or hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.name))
    error_message = "name is 6 to 30 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "subjects" {
  description = "Who may impersonate the service account, as GitHub's token subjects: \"repo:OWNER/REPO:ref:refs/heads/main\" for a branch, \"repo:OWNER/REPO:environment:production\" for an environment."
  type        = list(string)

  validation {
    condition     = length(var.subjects) > 0 && alltrue([for subject in var.subjects : can(regex("^repo:[^/*]+/[^/*:]+:.+", subject))])
    error_message = "Each subject names one owner and one repository in full (repo:OWNER/REPO:...)."
  }

  validation {
    condition     = alltrue([for subject in var.subjects : !strcontains(subject, "*")])
    error_message = "Subjects are matched exactly: name the branch or the environment instead of using a wildcard."
  }
}

variable "project_roles" {
  description = "Roles the workflows get on the project. roles/viewer is enough for a plan."
  type        = set(string)

  validation {
    condition     = length(setintersection(var.project_roles, ["roles/owner", "roles/editor"])) == 0
    error_message = "Owner and Editor are refused: give a pipeline the roles it needs."
  }
}

variable "create_pool" {
  description = "Create the project's GitHub pool. Set to false and pass pool_name in every stack after the first."
  type        = bool
  default     = true
}

variable "pool_id" {
  description = "ID of the workload identity pool."
  type        = string
  default     = "github"
}

variable "pool_name" {
  description = "Full name of the existing pool (projects/NUMBER/locations/global/workloadIdentityPools/ID), when create_pool is false."
  type        = string
  default     = null
}
