output "bucket" {
  description = "Name of the state bucket, for the backend block of every stack."
  value       = aws_s3_bucket.state.bucket
}
