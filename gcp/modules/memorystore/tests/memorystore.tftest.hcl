mock_provider "google" {}

variables {
  project_id = "test-project"
  name       = "test-cache"
  region     = "us-central1"
  network_id = "projects/test-project/global/networks/test"
}

run "private_with_auth_and_tls" {
  command = plan

  assert {
    condition     = google_redis_instance.this.connect_mode == "PRIVATE_SERVICE_ACCESS" && google_redis_instance.this.auth_enabled && google_redis_instance.this.transit_encryption_mode == "SERVER_AUTHENTICATION"
    error_message = "A private address, a password and TLS."
  }

  assert {
    condition     = google_redis_instance.this.tier == "STANDARD_HA"
    error_message = "By default a replica in another zone takes over."
  }
}

run "one_node_when_asked" {
  command = plan

  variables {
    high_availability = false
  }

  assert {
    condition     = google_redis_instance.this.tier == "BASIC"
    error_message = "Without high availability it is a single node."
  }
}
