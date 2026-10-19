mock_provider "aws" {}

variables {
  name               = "test"
  kubernetes_version = "1.34"
  subnet_ids         = ["subnet-a", "subnet-b"]
  admin_role_arns    = { platform = "arn:aws:iam::111111111111:role/platform-admin" }
}

run "private_by_default_and_admins_are_explicit" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access && !aws_eks_cluster.this.vpc_config[0].endpoint_public_access
    error_message = "With no ranges listed the Kubernetes API has no public endpoint."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API" && !aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions
    error_message = "Access goes through access entries and the creator gets no implicit admin."
  }

  assert {
    condition     = length(aws_eks_access_entry.admins) == 1 && contains(aws_eks_cluster.this.enabled_cluster_log_types, "audit")
    error_message = "One access entry per admin role, and the audit log is on."
  }

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].resources == toset(["secrets"]) && aws_kms_key.secrets.enable_key_rotation
    error_message = "Kubernetes secrets are encrypted with a rotating KMS key."
  }
}

run "the_api_opens_only_to_the_ranges_listed" {
  command = plan

  variables {
    api_allowed_cidrs = ["203.0.113.0/24"]
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_public_access && aws_eks_cluster.this.vpc_config[0].public_access_cidrs == toset(["203.0.113.0/24"])
    error_message = "The public endpoint exists and is limited to the ranges given."
  }
}

run "the_whole_internet_is_refused" {
  command = plan

  variables {
    api_allowed_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.api_allowed_cidrs]
}

run "more_min_than_max_nodes_is_refused" {
  command = plan

  variables {
    node_count = { min = 3, max = 2 }
  }

  expect_failures = [var.node_count]
}
