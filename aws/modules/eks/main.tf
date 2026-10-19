# An EKS cluster with managed nodes in private subnets.
#   - Who can use the cluster is decided by access entries (the EKS API), not by the aws-auth ConfigMap.
#   - Kubernetes secrets are encrypted with a KMS key of the cluster's own.
#   - The control plane's audit log goes to CloudWatch with a retention period.
#   - Pods get AWS permissions through Pod Identity (see modules/workload-identity), never through the nodes' role.

locals {
  addons = toset(["vpc-cni", "kube-proxy", "coredns", "eks-pod-identity-agent"])
}

resource "aws_kms_key" "secrets" {
  description             = "Envelope encryption of Kubernetes secrets in ${var.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name}-eks-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# Created here so that it has a retention period: EKS would otherwise create it and keep the logs forever.
resource "aws_cloudwatch_log_group" "control_plane" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "cluster" {
  name = "${var.name}-eks-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    # The API server is reachable from the internet only for the ranges listed, and not at all when the list is empty.
    endpoint_public_access = length(var.api_allowed_cidrs) > 0
    public_access_cidrs    = length(var.api_allowed_cidrs) > 0 ? var.api_allowed_cidrs : null
  }

  access_config {
    authentication_mode = "API"
    # Whoever runs the first apply does not become a hidden cluster admin: admins are the entries below.
    bootstrap_cluster_creator_admin_permissions = false
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.secrets.arn
    }
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [aws_iam_role_policy_attachment.cluster, aws_cloudwatch_log_group.control_plane]
}

resource "aws_eks_access_entry" "admins" {
  for_each      = var.admin_role_arns
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "admins" {
  for_each      = var.admin_role_arns
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admins]
}

resource "aws_iam_role" "nodes" {
  name = "${var.name}-eks-nodes"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# What a node needs to join the cluster, pull images and wire pod networking. Nothing an application needs.
resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
  ])
  role       = aws_iam_role.nodes.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.node_instance_types
  capacity_type   = var.node_capacity_type

  scaling_config {
    min_size     = var.node_count.min
    max_size     = var.node_count.max
    desired_size = var.node_count.min
  }

  update_config {
    max_unavailable = 1
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size] # the autoscaler owns this number after creation
  }

  depends_on = [aws_iam_role_policy_attachment.nodes]
}

resource "aws_eks_addon" "this" {
  for_each                    = local.addons
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  resolve_conflicts_on_update = "OVERWRITE"

  # coredns runs as pods and waits for nodes; the others are needed for nodes to become ready.
  depends_on = [aws_eks_node_group.this]
}
