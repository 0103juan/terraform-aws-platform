mock_provider "aws" {}

variables {
  bucket_name = "example-terraform-state"
}

run "private_versioned_and_encrypted" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_public_access_block.state.block_public_acls && aws_s3_bucket_public_access_block.state.block_public_policy &&
      aws_s3_bucket_public_access_block.state.ignore_public_acls && aws_s3_bucket_public_access_block.state.restrict_public_buckets
    )
    error_message = "Every kind of public access is blocked."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning is on, so an earlier state can be restored."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Without a KMS key the state is still encrypted, with S3's keys."
  }
}

run "a_key_of_your_own_switches_to_kms" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Given a key, the state is encrypted with it."
  }
}

run "an_invalid_bucket_name_is_refused" {
  command = plan

  variables {
    bucket_name = "Not_A_Bucket"
  }

  expect_failures = [var.bucket_name]
}
