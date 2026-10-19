# The Cloud Storage bucket that holds Terraform state. Applied once per project, by hand, with local state: it
# is the one thing that cannot keep its own state in the bucket it creates.
# The gcs backend locks with the bucket itself, so nothing else is needed for locking.

resource "google_storage_bucket" "state" {
  project                     = var.project_id
  name                        = var.bucket_name
  location                    = var.location
  force_destroy               = false
  uniform_bucket_level_access = true       # IAM only, no per-object ACLs
  public_access_prevention    = "enforced" # state holds every attribute of every resource, sensitive ones too

  # An earlier state can be restored after a bad apply or a corrupted write.
  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = var.versions_to_keep
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  dynamic "encryption" {
    for_each = var.kms_key_name == null ? [] : [var.kms_key_name]
    content {
      default_kms_key_name = encryption.value
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
