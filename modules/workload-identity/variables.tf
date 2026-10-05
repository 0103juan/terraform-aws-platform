variable "name" {
  description = "Name of the IAM role."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster the service account belongs to."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account."
  type        = string
}

variable "service_account" {
  description = "Kubernetes service account whose pods get the role."
  type        = string
}

variable "statements" {
  description = "What the workload may do: each statement allows a list of actions on a list of resources."
  type = list(object({
    sid       = string
    actions   = list(string)
    resources = list(string)
  }))

  validation {
    condition     = alltrue([for statement in var.statements : !contains(statement.actions, "*") && !contains(statement.resources, "*")])
    error_message = "A workload role names its actions and its resources: \"*\" is not accepted for either."
  }

  validation {
    condition     = length(var.statements) > 0
    error_message = "A role that allows nothing is a mistake: give at least one statement."
  }
}
