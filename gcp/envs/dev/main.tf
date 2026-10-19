# The development environment: the stack at its cheapest. Spot nodes, a zonal database that can be deleted,
# one cache node. An outage here costs an afternoon, not customers.

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  # Its own state file: nothing done to dev can touch another environment's state. Replace the bucket with the
  # one gcp/modules/state-backend created. The gcs backend locks by itself.
  backend "gcs" {
    bucket = "REPLACE-terraform-state"
    prefix = "analyst/dev"
  }
}

provider "google" {
  project = var.project_id
  region  = "us-central1"

  default_labels = {
    project     = "analyst"
    environment = "dev"
    managed-by  = "terraform"
  }
}

module "analyst" {
  source = "../../stacks/analyst"

  environment        = "dev"
  project_id         = var.project_id
  region             = "us-central1"
  cidr               = "10.30.0.0/16"
  kubernetes_version = "1.34"
  api_allowed_cidrs  = var.api_allowed_cidrs
  admin_members      = var.admin_members
  billing_account    = var.billing_account
  alert_emails       = var.alert_emails

  nodes          = { machine_type = "e2-standard-2", spot = true, min = 1, max = 2 }
  database       = { tier = "db-custom-1-3840", high_availability = false, backup_retention_days = 1, deletion_protection = false }
  cache          = { memory_size_gb = 1, high_availability = false }
  monthly_budget = 150
}
