# terraform-aws-platform

Terraform for running a containerised service on AWS: a network, an EKS cluster, PostgreSQL, a
Redis-compatible cache, and the identity plumbing between them. Written as reusable modules, composed into a
stack, and instantiated as two environments.

**Nothing here has been applied to an AWS account.** It is checked the ways code can be checked without one:
formatting, `terraform validate`, 32 tests that plan against a mocked provider, a linter and a security
scanner, all in CI. What that does and does not prove is under [Limits](#limits).

```
modules/            one concern each, usable on their own
  network/            VPC, three subnet tiers per zone, NAT, flow logs
  eks/                cluster, managed nodes, add-ons, access entries
  postgres/           RDS for PostgreSQL
  redis/              ElastiCache (Valkey or Redis)
  workload-identity/  AWS permissions for one Kubernetes service account
  github-oidc/        a role GitHub Actions assumes without stored keys
  state-backend/      the S3 bucket for Terraform state
stacks/analyst/     the modules composed into what one environment of a service needs
envs/dev, envs/prod the stack with each environment's values and its own state
```

The stack is what [secop-analyst](https://github.com/0103juan/secop-analyst) would run on: the same
Kubernetes manifests, with the Postgres and Redis pods replaced by managed services.

## Choices worth reading the code for

- **No secret passes through Terraform.** The database's master password is created and rotated by RDS in
  Secrets Manager (`manage_master_user_password`), so it is not in the state. The model provider's key gets a
  secret container here and its value from outside. A test asserts that `password` stays unset.
- **Access is granted to workloads, not addresses.** The database and the cache accept connections from
  security groups given by name, never from CIDR ranges. Pods get AWS permissions through EKS Pod Identity,
  bound to one service account, instead of through the nodes' role. The workload-identity module refuses a
  policy with `*` as an action or as a resource.
- **Nobody is an administrator by accident.** The cluster uses access entries, and the identity that creates
  it gets no implicit admin (`bootstrap_cluster_creator_admin_permissions = false`). The Kubernetes API has no
  public endpoint unless ranges are listed, and `0.0.0.0/0` is rejected by a validation.
- **CI deploys without stored keys.** `github-oidc` creates a role that a workflow assumes with a short-lived
  token. Its validations reject a subject that covers a whole organisation or every ref of a repository, which
  is how these roles usually end up assumable by a fork's pull request.
- **Three subnet tiers.** Public for load balancers and NAT, private for workloads, and a database tier with
  no route to the internet in either direction. The default security group is emptied.
- **The differences between dev and prod are the cost decisions, stated in one place each.** One NAT gateway
  or one per zone; spot or on-demand nodes; a database with or without a standby, deletable or protected.
  `envs/dev/main.tf` and `envs/prod/main.tf` are the same module call with different values.
- **State is isolated per environment** (a key each in an encrypted, versioned bucket that refuses plain
  HTTP) and locked with S3's own lock file, so there is no DynamoDB table.
- **Mistakes are caught at plan time.** Variables carry validations with messages that say what to do: a VPC
  range that is not a /16, a single availability zone, backups turned off, more minimum than maximum nodes.
  Each has a test that expects the failure.
- **An environment that is left running warns someone.** EKS's control plane and every NAT gateway are billed
  by the hour whether anything runs or not. Each environment has a monthly budget filtered by its
  `Environment` tag, which emails when 80 % is spent and when the forecast passes the whole amount; a budget
  with no address is refused at plan time.
- **A tag always names the same image.** The service's ECR repository has immutable tags, so a rollback goes
  back to exactly what ran, scans every image on push and expires untagged layers and old builds.
- **Explicit over looked-up.** Regions and availability zones are passed in, not read from data sources, so a
  plan makes no API call that is not about the resources themselves.

## Check it

Terraform 1.10 or newer; CI uses 1.15.8 and the AWS provider 6.x. No account or credentials are needed.

```
terraform fmt -check -recursive
for dir in modules/* stacks/* envs/*; do
  terraform -chdir=$dir init -backend=false
  terraform -chdir=$dir validate
  [ -d $dir/tests ] && terraform -chdir=$dir test
done
```

The linter (tflint with the AWS ruleset) and the scanner (trivy) run from their container images; the exact
commands are in [.github/workflows/ci.yml](.github/workflows/ci.yml).

## Use a module elsewhere

```hcl
module "deploy_role" {
  source = "github.com/0103juan/terraform-aws-platform//modules/github-oidc?ref=<commit>"   # pin a commit or a tag

  name        = "my-service-deploy"
  subjects    = ["repo:my-org/my-service:environment:production"]
  policy_arns = { deploy = aws_iam_policy.deploy.arn }
}
```

To apply an environment: create the state bucket once with `modules/state-backend`, put its name in the
`backend` block of `envs/<env>/main.tf`, copy `example.tfvars` to `terraform.tfvars` with real role ARNs,
then `terraform init` and `terraform plan` in that folder.

## Scanner findings that are accepted

CI fails on high and critical findings; there are none. These lower ones remain, on purpose:

| Finding | Why it stays |
|---|---|
| AWS-0077 backup retention is low, AWS-0177 no deletion protection | The values of `envs/dev`: a development database that can be thrown away. The module's defaults are 14 days and protected, and it refuses to turn backups off. |
| AWS-0017 log groups, AWS-0078 Performance Insights, AWS-0098 secrets: not encrypted with a customer-managed key | They are encrypted with keys AWS manages. A customer-managed key adds a key policy to maintain and a monthly charge per key; the modules take a key ARN where the data is the product (database storage, cache, state bucket). |
| AWS-0089 the state bucket has no access logging | Access logging needs a second bucket to write to. CloudTrail data events are the usual answer and belong to the account, not to this module. |

## Limits

- **Never applied.** `validate` checks the configuration against the provider's schema and the tests check
  what the plan would contain. Neither catches what only the AWS API knows: an instance class that is not
  offered in a zone, a Kubernetes or engine version that is not available, a service quota, a name that is
  taken, the order two resources really have to be created in. The first `apply` will find some of these.
- **A mocked provider returns made-up values for computed attributes,** so the tests assert on what the
  configuration sets, not on what AWS would return. The stack's test proves the modules fit together in the
  shape of each environment and little more.
- **No cost estimate.** The dev/prod choices are argued in comments, not priced. The budget warns after the
  money is being spent; it does not stop anything. Its filter only sees the `Environment` tag once it is
  activated as a cost allocation tag in the billing console.
- **The nodes are Graviton** (`t4g`, `m7g`), so the image must be built for `linux/arm64` (or for both
  architectures). An `amd64` image fails on them with `exec format error`.
- **Not included:** DNS and certificates, a load balancer controller and an ingress, autoscaling of the
  nodes, how the Kubernetes manifests read the secrets (an operator such as External Secrets), alarms and
  dashboards, backups to another region, and a pipeline that plans on pull requests and applies on merge.
- The cache has TLS and a security group, and no password or user-level access control.
- One region and one account. Separate accounts per environment is the better isolation and is not modelled.

## Licence

MIT. See [LICENSE](LICENSE).
