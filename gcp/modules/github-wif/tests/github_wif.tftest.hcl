mock_provider "google" {
  mock_resource "google_iam_workload_identity_pool" {
    defaults = {
      name = "projects/123456789012/locations/global/workloadIdentityPools/github"
    }
  }

  mock_resource "google_service_account" {
    defaults = {
      name  = "projects/test-project/serviceAccounts/my-service-deploy@test-project.iam.gserviceaccount.com"
      email = "my-service-deploy@test-project.iam.gserviceaccount.com"
    }
  }
}

variables {
  project_id    = "test-project"
  name          = "my-service-deploy"
  subjects      = ["repo:my-org/my-service:environment:production"]
  project_roles = ["roles/run.developer"]
}

run "only_the_listed_subjects_get_in" {
  command = plan

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub in [\"repo:my-org/my-service:environment:production\"]"
    error_message = "The provider rejects every token whose subject is not listed."
  }
}

run "the_binding_names_the_exact_subject" {
  command = apply # computed pool name from the mock

  assert {
    condition     = google_service_account_iam_member.github["repo:my-org/my-service:environment:production"].member == "principal://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/github/subject/repo:my-org/my-service:environment:production"
    error_message = "One principal per subject, not a principalSet over a whole repository."
  }
}

run "a_wildcard_is_refused" {
  command = plan

  variables {
    subjects = ["repo:my-org/my-service:*"]
  }

  expect_failures = [var.subjects]
}

run "a_whole_owner_is_refused" {
  command = plan

  variables {
    subjects = ["repo:my-org/*:ref:refs/heads/main"]
  }

  expect_failures = [var.subjects]
}

run "editor_is_refused" {
  command = plan

  variables {
    project_roles = ["roles/editor"]
  }

  expect_failures = [var.project_roles]
}
