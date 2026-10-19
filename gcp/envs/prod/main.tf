# The production environment: a standby for the database, a replica for the cache, on-demand nodes, and
# deletion protection on what holds data.

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  # Its own state file: nothing done to prod can touch another environment's state. Replace the bucket with the
  # one gcp/modules/state-backend created. The gcs backend locks by itself.
  backend "gcs" {
    bucket = "REPLACE-terraform-state"
    prefix = "analyst/prod"
  }
}

provider "google" {
  project = var.project_id
  region  = "us-central1"

  default_labels = {
    project     = "analyst"
    environment = "prod"
    managed-by  = "terraform"
  }
}

module "analyst" {
  source = "../../stacks/analyst"

  environment        = "prod"
  project_id         = var.project_id
  region             = "us-central1"
  cidr               = "10.31.0.0/16"
  kubernetes_version = "1.34"
  api_allowed_cidrs  = var.api_allowed_cidrs
  admin_members      = var.admin_members
  billing_account    = var.billing_account
  alert_emails       = var.alert_emails

  nodes          = { machine_type = "e2-standard-4", spot = false, min = 3, max = 6 }
  database       = { tier = "db-custom-2-7680", high_availability = true, backup_retention_days = 14, deletion_protection = true }
  cache          = { memory_size_gb = 2, high_availability = true }
  monthly_budget = 1500
}
