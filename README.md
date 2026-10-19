# terraform-aws-platform

Terraform for running a containerised service on **Google Cloud** and on **AWS**, with each cloud's own
services: a network, a Kubernetes cluster, PostgreSQL, Redis, an image registry, secrets, the identity plumbing
between them, a budget and alarms. Each cloud is written as reusable modules, composed into a stack and
instantiated as two environments. The two halves are independent: use one, the other, or both.

**Nothing here has been applied to a cloud account.** It is checked the ways code can be checked without one:
formatting, `terraform validate`, 64 tests that plan against mocked providers (30 for GCP, 34 for AWS), a linter
and a security scanner, all in CI. What that does and does not prove is under [Limits](#limits).

```
gcp/
  modules/              one concern each, usable on their own
    network/              VPC, subnet with pod and service ranges, Private Service Access, Cloud NAT, flow logs
    gke/                  regional private cluster, autoscaled node pool, KMS for secrets, Gateway API
    cloud-sql/            Cloud SQL for PostgreSQL, private IP, IAM database authentication
    memorystore/          Memorystore for Redis with AUTH and TLS
    workload-identity/    Google permissions for one Kubernetes service account
    github-wif/           a service account GitHub Actions impersonates without stored keys
    state-backend/        the Cloud Storage bucket for Terraform state
    cloud-run/            a Cloud Run service with its own identity, for workloads without a cluster
  stacks/analyst/       the modules composed into what one environment of a service needs
  envs/dev, envs/prod   the stack with each environment's values and its own state
aws/
  modules/              network, eks, postgres, redis, workload-identity, github-oidc, state-backend
  stacks/analyst/
  envs/dev, envs/prod
.github/workflows/
  ci.yml                format, validate, test, lint and scan both clouds on every push
  plan.yml              plan every environment against its cloud on pull requests, once configured
```

The stacks are what [secop-analyst](https://github.com/0103juan/secop-analyst) would run on: the same
Kubernetes manifests, with the Postgres and Redis pods replaced by managed services.

## The same platform on both clouds

| Piece | Google Cloud | AWS |
|---|---|---|
| Network | VPC with one regional subnet and secondary ranges for pods and services | VPC with public, private and database subnets in each zone |
| Private managed services | Private Service Access: a range peered with Google's services | Database subnets with no route to the internet |
| Outbound traffic | Cloud NAT, one per region | NAT gateway, one per zone or one in total |
| Kubernetes | GKE Standard, regional, private nodes | EKS with a managed node group in private subnets |
| Kubernetes secrets at rest | Cloud KMS key of the cluster's own | KMS key of the cluster's own |
| Pod permissions | Workload Identity: a Google service account per Kubernetes one | EKS Pod Identity: an IAM role per Kubernetes service account |
| Node autoscaling | Built into the node pool, profile `OPTIMIZE_UTILIZATION` | Cluster Autoscaler, with a role that can resize only this cluster's groups |
| Ingress | Gateway API built in (`gateway_api_config`) | AWS Load Balancer Controller, with the policy its maintainers publish |
| PostgreSQL | Cloud SQL, private IP, TLS only, IAM authentication: no password at all | RDS, TLS only, master password managed by RDS in Secrets Manager, IAM tokens for the service |
| Redis | Memorystore, AUTH and TLS, a replica with `STANDARD_HA` | ElastiCache, TLS, a replica in another zone when there are two nodes |
| Images | Artifact Registry, immutable tags, cleanup policies | ECR, immutable tags, scan on push, lifecycle policy |
| Secrets for the cluster | Secret Manager, read by External Secrets Operator | Secrets Manager, read by External Secrets Operator |
| CI without stored keys | Workload Identity Federation, exact token subjects | OIDC provider and an IAM role, exact token subjects |
| Terraform state | Cloud Storage bucket; the backend locks by itself | S3 bucket with S3's own lock file |
| Cost guard | Billing budget on the environment's project | AWS Budget filtered by the `Environment` tag |
| Alarms | Cloud Monitoring alert policies to email channels | CloudWatch alarms to an SNS topic with a customer-managed key |

## Choices worth reading the code for

On both clouds:

- **No secret passes through Terraform where the cloud can avoid it.** On GCP the service logs in to Cloud SQL as
  its own service account, so there is no database password anywhere. On AWS the master password is created
  and rotated by RDS in Secrets Manager, and the service connects with short-lived IAM tokens as the user
  `api`. The model provider's key gets an empty secret here and its value from outside.
- **The service's pods do not read secrets.** External Secrets Operator copies them into Kubernetes secrets,
  and its identity can read exactly the secrets of this stack. The service's own identity can only connect
  to the database.
- **Access is granted to workloads, not addresses.** Pods get cloud permissions through Workload Identity or
  Pod Identity, bound to one Kubernetes service account. Nodes run with the minimum: on GKE a service account
  with five narrow roles instead of the default account's Editor; on EKS the three node policies.
- **Nobody gets broad roles by accident.** The identity modules refuse `*` in AWS policies and the basic roles
  (Owner, Editor, Viewer) on GCP. Controllers whose maintainers publish their own policy (the AWS Load Balancer
  Controller) get it unchanged, in an inline policy of its own, so it is clear where the wildcards come from.
- **CI deploys without stored keys,** and the token subjects are matched exactly: a wildcard, a whole owner or
  a whole repository is refused at plan time, which is how these trusts usually end up open to a fork's pull
  request.
- **An environment that is left running warns someone.** A Kubernetes control plane and a NAT are billed by
  the hour whether anything runs or not. Each environment has a monthly budget that emails at 80 % spent and
  when the forecast passes the whole amount, plus alarms on the database's CPU, memory and storage and the
  cache's memory. A list of addresses that is empty is refused.
- **A tag always names the same image.** Both registries have immutable tags, so a rollback goes back to
  exactly what ran, and both expire untagged layers and old builds.
- **The differences between dev and prod are the cost decisions, stated in one place each:** spot or on-demand
  nodes, a standby database or not, deletable or protected, one cache node or a replica.
- **Mistakes are caught at plan time.** Variables carry validations with messages that say what to do. Each
  has a test that expects the failure.

On GCP:

- **Private by construction.** The VPC has no automatic subnets and no default firewall rules; nodes have no
  public address; the Kubernetes API has no public endpoint unless ranges are listed, and `0.0.0.0/0` is
  rejected; Cloud SQL and Memorystore have private addresses only.
- **Dataplane V2** enforces Kubernetes NetworkPolicy objects. Without it they are accepted and ignored.
- **Cloud SQL logs what an incident review asks for:** connections, disconnections, lock waits, checkpoints,
  temporary files and statements slower than a second.
- **APIs are turned on by the stack and left on when it is destroyed,** because turning one off breaks
  anything else in the project that uses it.
- **`cloud-run`** is a module of its own for services that do not need a cluster: its own service account,
  secrets read by reference at start, internal ingress and no invokers unless listed, and optional Direct
  VPC egress to reach Cloud SQL and Memorystore.

On AWS:

- **Nobody is a cluster administrator by accident.** The cluster uses access entries, and the identity that
  creates it gets no implicit admin.
- **Three subnet tiers,** and a database tier with no route to the internet in either direction.
- **The alerts topic is encrypted with a key of its own** whose policy lets CloudWatch publish: with the
  AWS-managed SNS key, the alarms would never arrive.

## Cluster add-ons

Terraform creates the identities; the controllers are installed into the cluster with Helm. Installing them
from the same apply would need the cluster to exist before the plan can be made. The service accounts must
have the names the identities are bound to.

On GKE the ingress controller and autoscaling are part of the cluster. Only External Secrets is added, with
its Kubernetes service account annotated with the Google service account from the `service_accounts` output:

```
helm install external-secrets external-secrets/external-secrets --version 2.13.0 \
  -n external-secrets --create-namespace \
  --set serviceAccount.name=external-secrets \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"=<email from the output>
```

On EKS, Pod Identity binds the roles to the service accounts by name, so no annotation is needed:

```
helm install external-secrets external-secrets/external-secrets --version 2.13.0 \
  -n external-secrets --create-namespace --set serviceAccount.name=external-secrets
helm install aws-load-balancer-controller eks/aws-load-balancer-controller --version 3.6.0 \
  -n kube-system --set clusterName=<cluster> --set serviceAccount.name=aws-load-balancer-controller
helm install cluster-autoscaler autoscaler/cluster-autoscaler -n kube-system \
  --set autoDiscovery.clusterName=<cluster> --set awsRegion=us-east-1 \
  --set rbac.serviceAccount.name=cluster-autoscaler --set image.tag=v1.36.1
```

The images in the AWS environments run on Graviton nodes (`t4g`, `m7g`): build them for `linux/arm64`.

## Check it

Terraform 1.10 or newer; CI uses 1.15.8, the Google provider 8.x and the AWS provider 6.x. No account or
credentials are needed.

```
terraform fmt -check -recursive
for dir in gcp/modules/* gcp/stacks/* gcp/envs/* aws/modules/* aws/stacks/* aws/envs/*; do
  terraform -chdir=$dir init -backend=false
  terraform -chdir=$dir validate
  [ -d $dir/tests ] && terraform -chdir=$dir test
done
```

The linter (tflint with the Google and AWS rulesets) and the scanner (trivy) run from their container images;
the exact commands are in [.github/workflows/ci.yml](.github/workflows/ci.yml).

## Plan on pull requests

[.github/workflows/plan.yml](.github/workflows/plan.yml) plans each environment against its real cloud on every
pull request and writes the plan to the run's summary. A plan only reads, and it is not billed. It stays off
until the repository variable `PLAN_ENABLED` is `true`. To turn it on:

1. Create the state bucket once per cloud with `state-backend`, and put the environments' state in it.
2. Create a read-only identity for the pipeline: `github-wif` with `project_roles = ["roles/viewer"]` on GCP,
   `github-oidc` with `ReadOnlyAccess` on AWS. The subjects are the GitHub environments the workflow runs in:
   `repo:OWNER/REPO:environment:plan-gcp-dev`, and so on. Both need read access to the state bucket.
3. Create the four GitHub environments (`plan-gcp-dev`, `plan-gcp-prod`, `plan-aws-dev`, `plan-aws-prod`)
   with the variables the workflow lists at its top.

## Use a module elsewhere

```hcl
module "deploy" {
  source = "github.com/0103juan/terraform-aws-platform//gcp/modules/github-wif?ref=<commit>"   # pin a commit or a tag

  project_id    = "my-project"
  name          = "my-service-deploy"
  subjects      = ["repo:my-org/my-service:environment:production"]
  project_roles = ["roles/run.developer", "roles/artifactregistry.writer"]
}

module "api" {
  source = "github.com/0103juan/terraform-aws-platform//gcp/modules/cloud-run?ref=<commit>"

  project_id = "my-project"
  name       = "my-service-api"
  region     = "us-central1"
  image      = "us-central1-docker.pkg.dev/my-project/apps/api@sha256:..."
  secrets    = { DATABASE_URL = "my-service-database-url" }
  invokers   = ["serviceAccount:frontend@my-project.iam.gserviceaccount.com"]
}
```

To apply an environment, the steps are the same on both clouds:

1. Create the state bucket once with `state-backend`.
2. Put its name in the `backend` block of `<cloud>/envs/<env>/main.tf`.
3. Copy `example.tfvars` to `terraform.tfvars` with real values.
4. Run `terraform init` and `terraform plan` in that folder.

## Scanner findings that are accepted

CI fails on high and critical findings; there are none. These lower ones remain, on purpose:

| Finding | Why it stays |
|---|---|
| AWS-0077 backup retention is low, AWS-0177 no deletion protection | The values of `aws/envs/dev`: a development database that can be thrown away. The module's defaults are 14 days and protected, and it refuses to turn backups off. The same holds for Cloud SQL in `gcp/envs/dev`. |
| AWS-0017 log groups, AWS-0033 the image registry, AWS-0078 Performance Insights, AWS-0098 secrets, GCP-0066 the state bucket: not encrypted with a customer-managed key | They are encrypted with keys the cloud manages. A customer-managed key adds a key policy to maintain and a monthly charge per key; the modules take a key where the data is the product (database storage, cache, state bucket) or where the cloud requires it (Kubernetes secrets, the alerts topic). |
| AWS-0089 the state bucket has no access logging | Access logging needs a second bucket to write to. CloudTrail data events are the usual answer and belong to the account, not to this module. |
| GCP-0021 long statements are logged | On purpose: statements slower than `slow_query_ms` (one second) are what finds a missing index. |

## Limits

- **Never applied.** `validate` checks the configuration against the providers' schemas and the tests check
  what the plan would contain. Neither catches what only the cloud's API knows: a machine type or instance class
  that is not offered in a zone, a Kubernetes or engine version that is not available, a quota, a name that is
  taken, an API that takes minutes to turn on, the order two resources really have to be created in. The first
  `apply` will find some of these.
- **A mocked provider returns made-up values for computed attributes,** so the tests assert on what the
  configuration sets, not on what the cloud would return. The stacks' tests prove the modules fit together in
  the shape of each environment and little more. They did catch one real error: a `for_each` over service
  account emails that are only known after apply.
- **No cost estimate.** The dev/prod choices are argued in comments, not priced. Budgets warn after the money
  is being spent; they do not stop anything. The GCP budget's currency must be the billing account's. The AWS
  budget sees the `Environment` tag only once it is activated as a cost allocation tag.
- **The Memorystore AUTH password is in the state** (and copied to Secret Manager for the workloads). Every
  attribute is in the state; the state bucket is private and versioned for that reason.
- **The database users for IAM authentication** are created by Terraform on Cloud SQL. On RDS the user `api`
  has to be created inside the database (`CREATE USER api; GRANT rds_iam TO api;`).
- **Not included:** DNS and certificates, dashboards, backups to another region, Karpenter (Cluster Autoscaler
  is used: it works with the existing node group and needs a much smaller policy), and a pipeline that applies
  on merge.
- One region and one account or project per environment. Separate accounts or projects per environment are
  assumed on GCP (`project_id`) and not modelled on AWS.

## Licence

MIT. See [LICENSE](LICENSE).
