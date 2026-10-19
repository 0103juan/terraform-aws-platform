# Plans against a mocked provider: no project, no credentials, nothing created.
mock_provider "google" {}

variables {
  project_id = "test-project"
  name       = "test"
  region     = "us-central1"
  cidr       = "10.30.0.0/16"
}

run "ranges_cut_from_the_16_without_overlap" {
  command = plan

  assert {
    condition = (
      google_compute_subnetwork.workloads.ip_cidr_range == "10.30.0.0/20" &&
      google_compute_global_address.managed_services.address == "10.30.32.0" &&
      [for range in google_compute_subnetwork.workloads.secondary_ip_range : range.ip_cidr_range] == ["10.30.64.0/18", "10.30.16.0/20"]
    )
    error_message = "Workloads take /20 block 0, services block 1, managed services block 2 and pods /18 block 1."
  }
}

run "private_by_construction" {
  command = plan

  assert {
    condition     = !google_compute_network.this.auto_create_subnetworks && google_compute_subnetwork.workloads.private_ip_google_access
    error_message = "No automatic subnets, and workloads reach Google APIs without a public address."
  }

  assert {
    condition     = google_compute_router_nat.this.source_subnetwork_ip_ranges_to_nat == "LIST_OF_SUBNETWORKS"
    error_message = "NAT covers the subnets listed, not every subnet that may be added later."
  }
}

run "a_range_that_is_not_a_16_is_refused" {
  command = plan

  variables {
    cidr = "10.30.0.0/20"
  }

  expect_failures = [var.cidr]
}

run "flow_logs_cannot_be_turned_off" {
  command = plan

  variables {
    flow_log_sampling = 0
  }

  expect_failures = [var.flow_log_sampling]
}
