mock_provider "aws" {}

variables {
  name        = "deploy"
  subjects    = ["repo:example/app:ref:refs/heads/main", "repo:example/app:environment:production"]
  policy_arns = { deploy = "arn:aws:iam::111111111111:policy/deploy" }
  # An existing provider, so that the trust policy is known at plan time and can be asserted on.
  create_provider = false
  provider_arn    = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
}

run "only_the_named_branch_and_environment_can_assume_the_role" {
  command = plan

  assert {
    condition     = tolist(jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]) == var.subjects
    error_message = "The trust policy carries exactly the subjects given."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "The token must have been issued for AWS."
  }
}

run "an_existing_provider_is_reused" {
  command = plan

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0 && output.provider_arn == var.provider_arn
    error_message = "No second provider is created in an account that has one."
  }
}

run "a_whole_organisation_is_refused" {
  command = plan

  variables {
    subjects = ["repo:example/*:ref:refs/heads/main"]
  }

  expect_failures = [var.subjects]
}

run "any_ref_of_a_repository_is_refused" {
  command = plan

  variables {
    subjects = ["repo:example/app:*"]
  }

  expect_failures = [var.subjects]
}

run "the_provider_is_created_when_the_account_has_none" {
  command = plan

  variables {
    create_provider = true
    provider_arn    = null
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1
    error_message = "The first stack in an account creates the provider."
  }
}
