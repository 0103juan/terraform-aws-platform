variable "project_id" {
  description = "Project of the service."
  type        = string
}

variable "name" {
  description = "Name of the service and account ID of its service account: 6 to 30 lowercase letters, digits or hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.name))
    error_message = "name is 6 to 30 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Region of the service."
  type        = string
}

variable "image" {
  description = "Container image, preferably by digest (…@sha256:…) so a deploy names exactly what runs."
  type        = string
}

variable "port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "health_path" {
  description = "Path the startup probe calls."
  type        = string
  default     = "/healthz"
}

variable "env" {
  description = "Plain environment variables. Anything secret goes in secrets."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Environment variables read from Secret Manager, as a map from the variable's name to the secret's ID."
  type        = map(string)
  default     = {}
}

variable "ingress" {
  description = "Who can reach the service over the network: INGRESS_TRAFFIC_INTERNAL_ONLY, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER or INGRESS_TRAFFIC_ALL."
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  validation {
    condition     = contains(["INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER", "INGRESS_TRAFFIC_ALL"], var.ingress)
    error_message = "ingress is INGRESS_TRAFFIC_INTERNAL_ONLY, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER or INGRESS_TRAFFIC_ALL."
  }
}

variable "invokers" {
  description = "IAM members allowed to call the service. allUsers makes it public, which has to be written on purpose."
  type        = set(string)
  default     = []
}

variable "instances" {
  description = "Fewest and most instances. A minimum above 0 keeps them warm and is billed while idle."
  type = object({
    min = number
    max = number
  })
  default = { min = 0, max = 5 }

  validation {
    condition     = var.instances.min >= 0 && var.instances.max >= 1 && var.instances.max >= var.instances.min
    error_message = "instances needs min >= 0, max >= 1 and max >= min."
  }
}

variable "cpu" {
  description = "CPU limit per instance."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit per instance."
  type        = string
  default     = "512Mi"
}

variable "concurrency" {
  description = "Requests one instance serves at once."
  type        = number
  default     = 80
}

variable "timeout_seconds" {
  description = "Longest a request may take."
  type        = number
  default     = 300
}

variable "vpc" {
  description = "Network and subnet for Direct VPC egress to private addresses. Null for none."
  type = object({
    network    = string
    subnetwork = string
  })
  default = null
}

variable "deletion_protection" {
  description = "Refuse to delete the service until this is set to false in a change of its own."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels of the service."
  type        = map(string)
  default     = {}
}
