variable "name" {
  description = "Name of the IAM role."
  type        = string
}

variable "subjects" {
  description = "Who may assume the role, as GitHub's token subjects: \"repo:OWNER/REPO:ref:refs/heads/main\" for a branch, \"repo:OWNER/REPO:environment:production\" for an environment."
  type        = list(string)

  validation {
    condition     = length(var.subjects) > 0 && alltrue([for subject in var.subjects : can(regex("^repo:[^/*]+/[^/*:]+:.+", subject))])
    error_message = "Each subject names one owner and one repository in full (repo:OWNER/REPO:...). A wildcard in either would let other repositories assume the role."
  }

  validation {
    condition     = alltrue([for subject in var.subjects : !endswith(subject, ":*")])
    error_message = "A subject ending in \":*\" lets any branch, tag or pull request of the repository assume the role, forks' pull requests included. Name the branch or the environment."
  }
}

variable "policy_arns" {
  description = "Policies to attach, as a map from a name to the policy's ARN."
  type        = map(string)
}

variable "create_provider" {
  description = "Create the account's OIDC provider for GitHub. There can be only one per account: set this to false and pass provider_arn in every stack after the first."
  type        = bool
  default     = true
}

variable "provider_arn" {
  description = "ARN of the existing OIDC provider for GitHub, when create_provider is false."
  type        = string
  default     = null
}
