mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789012"
    }
  }
}

variables {
  project_id          = "test-project"
  name                = "test-cluster"
  region              = "us-central1"
  kubernetes_version  = "1.34"
  network             = "projects/test-project/global/networks/test"
  subnetwork          = "projects/test-project/regions/us-central1/subnetworks/test-workloads"
  pods_range_name     = "pods"
  services_range_name = "services"
}

run "private_and_encrypted_by_default" {
  command = plan

  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].enable_private_nodes && google_container_cluster.this.private_cluster_config[0].enable_private_endpoint
    error_message = "Nodes have no public address, and with no ranges listed the API is private too."
  }

  assert {
    condition     = google_container_cluster.this.database_encryption[0].state == "ENCRYPTED"
    error_message = "Kubernetes secrets are encrypted with the cluster's KMS key."
  }

  assert {
    condition     = google_kms_crypto_key_iam_member.gke.member == "serviceAccount:service-123456789012@container-engine-robot.iam.gserviceaccount.com"
    error_message = "The key is granted to the GKE service agent of this project, and to no one else."
  }

  assert {
    condition     = google_container_cluster.this.workload_identity_config[0].workload_pool == "test-project.svc.id.goog"
    error_message = "Workload Identity is on."
  }
}

run "nodes_run_with_least_privilege" {
  command = plan

  assert {
    condition     = google_container_node_pool.this.node_config[0].workload_metadata_config[0].mode == "GKE_METADATA"
    error_message = "Pods cannot read the node's credentials from the metadata server."
  }

  assert {
    condition     = length(google_project_iam_member.nodes) == 5 && !contains([for member in google_project_iam_member.nodes : member.role], "roles/editor")
    error_message = "Nodes get five narrow roles, not the default service account's Editor."
  }
}

run "the_api_opens_only_to_the_ranges_listed" {
  command = plan

  variables {
    api_allowed_cidrs = ["203.0.113.0/24"]
  }

  assert {
    condition     = !google_container_cluster.this.private_cluster_config[0].enable_private_endpoint && length(google_container_cluster.this.master_authorized_networks_config[0].cidr_blocks) == 1
    error_message = "The public endpoint exists only for the range given."
  }
}

run "the_whole_internet_is_refused" {
  command = plan

  variables {
    api_allowed_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.api_allowed_cidrs]
}

run "more_minimum_than_maximum_nodes_is_refused" {
  command = plan

  variables {
    node_count = { min = 3, max = 2 }
  }

  expect_failures = [var.node_count]
}
