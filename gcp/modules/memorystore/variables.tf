variable "project_id" {
  description = "Project of the instance."
  type        = string
}

variable "name" {
  description = "Name of the instance."
  type        = string
}

variable "region" {
  description = "Region of the instance."
  type        = string
}

variable "network_id" {
  description = "VPC with Private Service Access the instance takes its address from."
  type        = string
}

variable "high_availability" {
  description = "Keep a replica in another zone that takes over (STANDARD_HA). False is one node (BASIC)."
  type        = bool
  default     = true
}

variable "memory_size_gb" {
  description = "Memory of the instance."
  type        = number
  default     = 1
}

variable "redis_version" {
  description = "Redis version, as Memorystore names it."
  type        = string
  default     = "REDIS_7_2"
}

variable "labels" {
  description = "Labels of the instance."
  type        = map(string)
  default     = {}
}
