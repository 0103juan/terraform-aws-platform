variable "project_id" {
  description = "Project of the bucket."
  type        = string
}

variable "bucket_name" {
  description = "Name of the bucket. Bucket names are global: include the organisation or project."
  type        = string
}

variable "location" {
  description = "Location of the bucket, a region or a multi-region such as US."
  type        = string
}

variable "versions_to_keep" {
  description = "Earlier versions of each state file kept."
  type        = number
  default     = 30
}

variable "kms_key_name" {
  description = "Cloud KMS key that encrypts the bucket. Null leaves it on Google's own encryption, which is always on."
  type        = string
  default     = null
}
