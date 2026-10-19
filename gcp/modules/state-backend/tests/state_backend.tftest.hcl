mock_provider "google" {}

variables {
  project_id  = "test-project"
  bucket_name = "test-org-terraform-state"
  location    = "US"
}

run "private_and_versioned" {
  command = plan

  assert {
    condition     = google_storage_bucket.state.public_access_prevention == "enforced" && google_storage_bucket.state.uniform_bucket_level_access
    error_message = "The bucket cannot be made public and has no per-object ACLs."
  }

  assert {
    condition     = google_storage_bucket.state.versioning[0].enabled && !google_storage_bucket.state.force_destroy
    error_message = "Earlier states are kept, and a destroy does not empty the bucket."
  }
}
