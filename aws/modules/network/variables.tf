variable "name" {
  description = "Prefix for every resource name, for example \"analyst-dev\"."
  type        = string
}

variable "region" {
  description = "Region of the VPC. Passed in instead of read from the provider, so that a plan needs no API call."
  type        = string
}

variable "cidr" {
  description = "IPv4 range of the VPC. Must be a /16: the subnet layout divides it into /20s."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr, 0)) && endswith(var.cidr, "/16")
    error_message = "cidr must be a valid IPv4 /16, for example 10.20.0.0/16."
  }
}

variable "availability_zones" {
  description = "Zones to spread the subnets over. Two at least, because a database subnet group and a load balancer need two; four at most, because of the subnet layout."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 4
    error_message = "Give between two and four availability zones."
  }

  validation {
    condition     = length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "The availability zones must be different from each other."
  }
}

variable "single_nat_gateway" {
  description = "One NAT gateway for the whole VPC instead of one per zone. Cheaper, and an outage of that zone cuts outbound traffic for all of them: for environments that can afford it."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Days the VPC flow logs are kept."
  type        = number
  default     = 30
}

variable "log_kms_key_arn" {
  description = "KMS key that encrypts the flow logs. Null leaves them on the service's own key."
  type        = string
  default     = null
}

variable "public_subnet_tags" {
  description = "Extra tags for the public subnets, such as the one a Kubernetes load balancer controller looks for."
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Extra tags for the private subnets."
  type        = map(string)
  default     = {}
}
