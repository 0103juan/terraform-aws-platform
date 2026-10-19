# Plans against a mocked provider: no account, no credentials, nothing created.
mock_provider "aws" {}

variables {
  name               = "test"
  region             = "us-east-1"
  cidr               = "10.20.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

run "three_tiers_per_zone_without_overlap" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3 && length(aws_subnet.database) == 3
    error_message = "Each zone gets a public, a private and a database subnet."
  }

  assert {
    condition = (
      aws_subnet.public["us-east-1a"].cidr_block == "10.20.0.0/20" &&
      aws_subnet.private["us-east-1a"].cidr_block == "10.20.64.0/20" &&
      aws_subnet.database["us-east-1c"].cidr_block == "10.20.160.0/20"
    )
    error_message = "The tiers take the /20 blocks 0-3, 4-7 and 8-11 of the /16."
  }

  assert {
    condition     = length(distinct(concat(values(aws_subnet.public)[*].cidr_block, values(aws_subnet.private)[*].cidr_block, values(aws_subnet.database)[*].cidr_block))) == 9
    error_message = "No two subnets share a range."
  }
}

run "a_nat_gateway_per_zone_by_default" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "Without single_nat_gateway every zone has its own way out."
  }
}

run "one_nat_gateway_when_asked" {
  command = plan

  variables {
    single_nat_gateway = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_route.private_nat) == 3
    error_message = "A single NAT gateway still serves the private subnets of every zone."
  }
}

run "a_range_that_is_not_a_16_is_refused" {
  command = plan

  variables {
    cidr = "10.20.0.0/24"
  }

  expect_failures = [var.cidr]
}

run "one_zone_is_refused" {
  command = plan

  variables {
    availability_zones = ["us-east-1a"]
  }

  expect_failures = [var.availability_zones]
}
