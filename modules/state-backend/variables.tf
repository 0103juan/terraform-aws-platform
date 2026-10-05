variable "bucket_name" {
  description = "Name of the bucket. S3 bucket names are unique across all of AWS, so include the account or the organisation."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name is 3 to 63 characters: lowercase letters, digits, dots and hyphens."
  }
}

variable "kms_key_arn" {
  description = "KMS key that encrypts the state. Null uses S3's own keys. The state is encrypted either way."
  type        = string
  default     = null
}

variable "keep_old_versions_days" {
  description = "Days an overwritten version of a state file is kept before it is deleted."
  type        = number
  default     = 90
}
