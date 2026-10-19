# A regional GKE Standard cluster with private nodes.
#   - Nodes have no public address, and the API is reachable from the internet only for the ranges listed.
#   - Kubernetes secrets are encrypted with a Cloud KMS key of the cluster's own.
#   - Nodes run as a service account that can write logs and metrics and pull images, and nothing else.
#   - Pods get Google permissions through Workload Identity (see modules/workload-identity), never the nodes'.
#   - The node pool scales itself between the bounds given; Gateway API is on for ingress.
#
# The project number is looked up because the GKE service agent that uses the KMS key is named after it.

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_kms_key_ring" "this" {
  project  = var.project_id
  name     = "${var.name}-gke"
  location = var.region
}

resource "google_kms_crypto_key" "secrets" {
  name            = "secrets"
  key_ring        = google_kms_key_ring.this.id
  rotation_period = "7776000s" # 90 days
}

resource "google_kms_crypto_key_iam_member" "gke" {
  crypto_key_id = google_kms_crypto_key.secrets.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.this.number}@container-engine-robot.iam.gserviceaccount.com"
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = "Nodes of ${var.name}"
}

# What a node needs to report and pull images. The default compute service account would bring Editor.
resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project             = var.project_id
  name                = var.name
  location            = var.region # regional: the control plane is replicated across the region's zones
  network             = var.network
  subnetwork          = var.subnetwork
  min_master_version  = var.kubernetes_version
  deletion_protection = var.deletion_protection

  # The default pool cannot be configured; it is replaced by the one below.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = var.release_channel
  }

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = length(var.api_allowed_cidrs) == 0
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.api_allowed_cidrs
      content {
        cidr_block   = cidr_blocks.value
        display_name = "allowed ${cidr_blocks.key}"
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  database_encryption {
    state    = "ENCRYPTED"
    key_name = google_kms_crypto_key.secrets.id
  }

  enable_shielded_nodes = true
  resource_labels       = var.labels

  # Dataplane V2 (eBPF) enforces Kubernetes NetworkPolicy objects; without it they are accepted and ignored.
  datapath_provider = "ADVANCED_DATAPATH"

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # Scale down eagerly: an idle node is money, and the pool scales up again when pods wait.
  cluster_autoscaling {
    autoscaling_profile = "OPTIMIZE_UTILIZATION"
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.gke]
}

resource "google_container_node_pool" "this" {
  project  = var.project_id
  name     = "default"
  cluster  = google_container_cluster.this.id
  location = var.region

  # Totals across the region's zones. Unlike EKS, GKE resizes the pool by itself within these bounds.
  autoscaling {
    total_min_node_count = var.node_count.min
    total_max_node_count = var.node_count.max
    location_policy      = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.machine_type
    image_type      = "COS_CONTAINERD" # Container-Optimized OS: read-only root, built for running containers
    resource_labels = var.labels
    spot            = var.spot
    disk_size_gb    = var.disk_size_gb
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"] # IAM decides; scopes are legacy

    workload_metadata_config {
      mode = "GKE_METADATA" # pods see the metadata server of Workload Identity, not the node's credentials
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}

# Who administers the cluster. In GKE, Kubernetes access follows IAM: this role is cluster-admin.
resource "google_project_iam_member" "admins" {
  for_each = var.admin_members
  project  = var.project_id
  role     = "roles/container.admin"
  member   = each.value
}
