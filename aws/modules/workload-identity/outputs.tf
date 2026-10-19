output "role_arn" {
  description = "ARN of the role the service account's pods get."
  value       = aws_iam_role.this.arn
}
