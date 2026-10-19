variable "project_id" {
  description = "Project of this environment."
  type        = string
}

variable "billing_account" {
  description = "Billing account the budget is created in. Account-specific, so it comes from a tfvars file or the pipeline."
  type        = string
}

variable "alert_emails" {
  description = "Who hears about the environment's cost and alarms."
  type        = list(string)
}

variable "admin_members" {
  description = "IAM members that administer the cluster."
  type        = set(string)
  default     = []
}

variable "api_allowed_cidrs" {
  description = "Address ranges that may reach the Kubernetes API, such as an office or a VPN."
  type        = list(string)
  default     = []
}
