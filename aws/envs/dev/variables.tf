variable "admin_role_arns" {
  description = "IAM roles that administer the cluster, as a map from a name to the role's ARN. Account-specific, so it comes from a tfvars file or the pipeline."
  type        = map(string)
}

variable "api_allowed_cidrs" {
  description = "Address ranges that may reach the Kubernetes API, such as an office or a VPN."
  type        = list(string)
  default     = []
}

variable "alert_emails" {
  description = "Who hears about the environment's cost and alarms. Account-specific, so it comes from a tfvars file or the pipeline."
  type        = list(string)
}
