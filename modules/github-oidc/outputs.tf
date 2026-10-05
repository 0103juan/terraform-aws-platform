output "role_arn" {
  description = "ARN to give to aws-actions/configure-aws-credentials as role-to-assume."
  value       = aws_iam_role.this.arn
}

output "provider_arn" {
  description = "ARN of the account's OIDC provider for GitHub, for other stacks in the same account."
  value       = local.provider_arn
}
