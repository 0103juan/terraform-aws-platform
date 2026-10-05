mock_provider "aws" {}

variables {
  name            = "test-api"
  cluster_name    = "test"
  namespace       = "app"
  service_account = "api"
  statements = [{
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:us-east-1:111111111111:secret:db-abc123"]
  }]
}

run "the_role_is_for_pods_and_bound_to_one_service_account" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "Only EKS Pod Identity can assume the role."
  }

  assert {
    condition     = aws_eks_pod_identity_association.this.namespace == "app" && aws_eks_pod_identity_association.this.service_account == "api"
    error_message = "The role is bound to one service account in one namespace."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.this.policy).Statement[0].Action == ["secretsmanager:GetSecretValue"]
    error_message = "The policy allows what was asked and nothing else."
  }
}

run "a_wildcard_action_is_refused" {
  command = plan

  variables {
    statements = [{ sid = "Everything", actions = ["*"], resources = ["arn:aws:s3:::bucket"] }]
  }

  expect_failures = [var.statements]
}

run "a_wildcard_resource_is_refused" {
  command = plan

  variables {
    statements = [{ sid = "Anywhere", actions = ["s3:GetObject"], resources = ["*"] }]
  }

  expect_failures = [var.statements]
}
