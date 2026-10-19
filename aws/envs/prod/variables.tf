variable "admin_role_arns" {
  description = "IAM roles that administer the cluster, as a map from a name to the role's ARN. Account-specific, so it comes from a tfvars file or the pipeline."
  type        = map(string)
}

variable "alert_emails" {
  description = "Who hears about the environment's cost and alarms. Account-specific, so it comes from a tfvars file or the pipeline."
  type        = list(string)
}
