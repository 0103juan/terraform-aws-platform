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
  count = length(var.statements) > 0 ? 1 : 0
  name  = "workload"
  role  = aws_iam_role.this.id
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

# A policy published by a controller's maintainers, such as the AWS Load Balancer Controller's. It is applied
# as published, wildcards included, because a hand-trimmed copy breaks on the controller's next release.
resource "aws_iam_role_policy" "vendor" {
  count  = var.vendor_policy_json == null ? 0 : 1
  name   = "vendor"
  role   = aws_iam_role.this.id
  policy = var.vendor_policy_json
}

resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.this.arn
}
