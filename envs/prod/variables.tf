variable "admin_role_arns" {
  description = "IAM roles that administer the cluster, as a map from a name to the role's ARN. Account-specific, so it comes from a tfvars file or the pipeline."
  type        = map(string)
}

variable "budget_emails" {
  description = "Who hears about the environment's cost. Account-specific, so it comes from a tfvars file or the pipeline."
  type        = list(string)
}
