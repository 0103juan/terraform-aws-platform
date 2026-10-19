# A VPC for one environment in one region.
#   - One subnet for workloads, with secondary ranges for GKE's pods and services (VPC-native).
#   - Private Service Access: a reserved range peered with Google's services, so Cloud SQL and Memorystore get
#     private addresses and nothing public. It plays the part of AWS's database subnets.
#   - Cloud NAT for outbound traffic. Subnets are regional in GCP, so there is no NAT-per-zone decision to make.
#   - Flow logs on the subnet.
#
# Layout of the /16 (cidr), in /20 blocks: 0 workloads, 1 services, 2 Private Service Access; /18 block 1 pods.

locals {
  workloads_range = cidrsubnet(var.cidr, 4, 0)
  services_range  = cidrsubnet(var.cidr, 4, 1)
  managed_range   = cidrsubnet(var.cidr, 4, 2)
  pods_range      = cidrsubnet(var.cidr, 2, 1)
}

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = var.name
  auto_create_subnetworks = false # no subnet in every region of the world, and no default firewall rules
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "workloads" {
  project       = var.project_id
  name          = "${var.name}-workloads"
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = local.workloads_range

  # Workloads with no public address still reach Google APIs (Artifact Registry, Secret Manager, logging).
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = local.pods_range
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = local.services_range
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = var.flow_log_sampling
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# The range Google's managed services take their addresses from, peered into this VPC.
resource "google_compute_global_address" "managed_services" {
  project       = var.project_id
  name          = "${var.name}-managed-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = cidrhost(local.managed_range, 0)
  prefix_length = 20
  network       = google_compute_network.this.id
}

resource "google_service_networking_connection" "managed_services" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.managed_services.name]
}

resource "google_compute_router" "this" {
  project = var.project_id
  name    = var.name
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  project                            = var.project_id
  name                               = var.name
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  # Only the workloads subnet goes out through NAT, pods included.
  subnetwork {
    name                    = google_compute_subnetwork.workloads.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
