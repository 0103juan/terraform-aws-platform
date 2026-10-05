# AWS permissions for one Kubernetes service account, through EKS Pod Identity.
# The pods that run as that service account get this role and no other pod does: the alternative, putting
# the permissions on the nodes' role, gives them to everything that runs on the node.

resource "aws_iam_role" "this" {
  name = var.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "this" {
  name = "workload"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [for statement in var.statements : {
      Sid      = statement.sid
      Effect   = "Allow"
      Action   = statement.actions
      Resource = statement.resources
    }]
  })
}

resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.this.arn
}
