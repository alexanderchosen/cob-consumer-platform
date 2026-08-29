# COB — Internal AWS Infrastructure Provisioning Platform

**Beejan Technologies · Platform Engineering**

COB is an internal Terraform platform that lets engineering teams provision standardised, secure-by-default AWS infrastructure through a handful of clean inputs without hand-building it, and without needing to understand what's happening underneath.

## Contents

- [The problem this solves](#the-problem-this-solves)
- [What COB provides](#what-cob-provides)
- [Capability details](#capability-details)
- [Repository structure](#repository-structure)
- [How a team consumes COB](#how-a-team-consumes-cob)
- [Naming and tagging](#naming-and-tagging)
- [Environments and free-tier strategy](#environments-and-free-tier-strategy)
- [Consumer example and expected outputs](#consumer-example-and-expected-outputs)
- [Security considerations](#security-considerations)
- [Architecture](#architecture)
- [Architectural decisions and trade-offs](#architectural-decisions-and-trade-offs)
- [Assumptions](#assumptions)
- [Known limitations](#known-limitations)
- [Getting started](#getting-started)

---

## The problem this solves

Before COB, every team asking Platform Engineering for infrastructure got a slightly different result — some S3 buckets encrypted, some not; inconsistent tagging; network and IAM configurations rebuilt from scratch each time. That made infrastructure slower to provision, harder to secure consistently, and harder to reason about as the engineering org grew.

COB replaces *"we need infrastructure, can Platform Engineering build it?"* with *"we provision what we need ourselves, using the company's standard modules."*

## What COB provides

Six reusable capabilities, each bundling every resource needed to make that capability secure and usable — not a thin wrapper around a single AWS resource.

| Capability | Module | What it bundles |
| --- | --- | --- |
| Networking | `modules/networking` | VPC, public/private subnets across 2+ AZs, routing, hardened default security group, flow logs |
| Identity & access | `modules/iam` | Least-privilege workload roles, with a hard guardrail against wildcard permissions |
| Object storage | `modules/storage-s3` | Encrypted, versioned, lifecycle-managed S3 buckets with public access unconditionally blocked |
| Compute | `modules/compute-ec2`, `modules/compute-ecs` | EC2 instances, and containerised workloads on ECS (EC2 launch type) — both wired to networking and IAM automatically |
| Relational database | `modules/database-rds` | Private, encrypted RDS instance with credentials in Secrets Manager, reachable only from a named application security group |
| Data platform | `modules/data-platform` | Glue Catalog + crawler over an S3 prefix, and an Athena workgroup with encrypted query results |

The table above is the quick-scan version. Full reasoning, inputs, outputs, and scope for each one follows immediately below.

## Capability details

#### Networking — `modules/networking`

- **The ask:** give a workload an isolated, correctly segmented place to run.
- **Key inputs:** `name_prefix`, `vpc_cidr`, `az_count`, `enable_nat_gateway`, `enable_flow_logs`
- **Key outputs:** `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `default_security_group_id`
- **Secure by default:** private subnets get no internet route unless NAT is explicitly turned on; the VPC's default security group is stripped of every rule; flow logs are on unless disabled.
- **Out of scope (v1):** VPN/Direct Connect, Transit Gateway, VPC peering.

#### Identity & access — `modules/iam`

- **The ask:** let a workload talk to the AWS services it needs — nothing more.
- **Key inputs:** `name_prefix`, `purpose`, `trusted_service` (`ecs-tasks`/`ec2`), `s3_read_arns`, `s3_write_arns`, `secrets_read_arns`
- **Key outputs:** `role_arn`, `role_name`, `instance_profile_name`
- **Secure by default:** a validation block physically rejects a wildcard (`"*"`) resource ARN at `plan` time — least privilege is enforced in code, not left as a guideline.
- **Out of scope (v1):** federated/SSO roles, cross-account access.

#### Object storage — `modules/storage-s3`

- **The ask:** give a team somewhere safe to put data, matched to how sensitive it is.
- **Key inputs:** `name_prefix`, `purpose`, `data_classification` (`public`/`internal`/`sensitive`), `lifecycle_days`, `enable_versioning`
- **Key outputs:** `bucket_id`, `bucket_arn`, `bucket_name`, `kms_key_arn`
- **Secure by default:** public access is blocked unconditionally (not a variable); encryption is always on; a lifecycle rule expires both current *and* old object versions, so cost doesn't grow unbounded.
- **Trade-off:** S3 bucket names must be globally unique across all of AWS, so the module appends a random suffix itself — the consumer never has to solve AWS's uniqueness problem by hand.
- **Cost note:** `data_classification = "sensitive"` creates a dedicated KMS key at a flat **$1/month regardless of use** — use `"internal"` or `"public"` unless you specifically need it.
- **Out of scope (v1):** cross-region replication, static website hosting.

#### Compute — `modules/compute-ec2`, `modules/compute-ecs`

- **The ask:** run an application, correctly networked and permissioned, without wiring subnets/security groups/IAM roles by hand.
- **Key inputs:** `name_prefix`, `purpose`, `vpc_id`, `subnet_ids`, `container_image`/`container_port` (ECS), `instance_type`, `min_size`/`max_size`/`desired_capacity`, `allowed_ingress_cidr`, plus `s3_read_arns`/`s3_write_arns`/`secrets_read_arns` (passed straight through to the workload's IAM role).
- **Key outputs:** `cluster_name`, `service_name`, `instance_security_group_id`, `task_role_arn`
- **Trade-off:** `compute-ecs` uses the **EC2 launch type** (a launch template, an Auto Scaling Group, and an ECS capacity provider) instead of Fargate. That's more infrastructure to manage, but Fargate has no AWS free-tier coverage at all, while EC2 draws from the account's 750 free hours/month.
- **Limitation:** the container's port maps to a fixed host port in `bridge` networking mode, so only one task can run per EC2 instance at a time.
- **Out of scope (v1):** auto-scaling policies, blue/green deployment.

#### Relational database — `modules/database-rds`

- **The ask:** a managed database a team doesn't have to think about backups or placement for.
- **Key inputs:** `name_prefix`, `purpose`, `vpc_id`, `subnet_ids`, `app_security_group_id`, `engine`, `engine_version`, `size_tier`, `multi_az`, `backup_retention_days`, `deletion_protection`
- **Key outputs:** `db_endpoint`, `db_port`, `credentials_secret_arn`
- **Secure by default:** never publicly accessible and always encrypted — both hardcoded, not variables.
- **Trade-off:** the database's security group allows traffic only from a *named application security group*, not an IP range — a much stronger form of isolation, at the cost of the consumer having to pass in that security group ID explicitly.
- **Honest caveat:** the database password is generated and stored in Secrets Manager rather than a plain variable, but Terraform's *state file* still contains it in plaintext, because Terraform has to know the value to manage the resource. The encrypted, access-controlled state bucket mitigates this; it doesn't eliminate it.
- **Cost note:** Multi-AZ isn't free-tier eligible, so it defaults to `false`.
- **Out of scope (v1):** read replicas, cross-region DR, a custom parameter group (uses the AWS default).

#### Data platform — `modules/data-platform`

- **The ask:** let analysts query data already sitting in S3, using SQL, without per-dataset manual setup.
- **Key inputs:** `name_prefix`, `purpose`, `source_bucket_arn`, `source_bucket_name`, `source_prefix`, `crawler_schedule`
- **Key outputs:** `glue_database_name`, `athena_workgroup_name`, `crawler_name`, `results_bucket_name`
- **Secure by default:** Athena query results are always encrypted; the crawler's IAM role can only ever read the one S3 prefix it's told to crawl, never the whole bucket.
- **Trade-off:** this module composes `modules/storage-s3` internally for its own Athena results bucket, rather than reimplementing bucket logic — proof the platform reuses its own capabilities the same way an external team would.
- **Out of scope (v1):** Lake Formation fine-grained permissions, cross-account catalog sharing.

## Repository structure

```
cob/
├── modules/            Reusable capability modules — the actual product
├── environments/       dev and prod root configs that compose modules
├── examples/           Points to environments/ as the real example consumers
├── docs/               Architecture diagram image
└── README.md           full platform documentation
```

## How a team consumes COB

A consumer never edits anything inside `modules/`. They write a short root config, in their own `environments/<environment_name>/main.tf`, calling the capability they need:

```hcl
module "storage" {
  source  = "../../modules/storage-s3"
  name_prefix = "cob-dev-s3"
  purpose = "uploads"
  data_classification = "internal"
}
```

Three lines of intent (`purpose`, `data_classification`) produce a fully encrypted, versioned, lifecycle-managed, public-access-blocked bucket — every security decision is made by the module, not the consumer.

## Naming and tagging

Every resource follows **`{project}-{environment}-{capability}-{purpose}`** — e.g. `cob-prod-s3-uploads`. Two rules make this consistent everywhere:

- The **environment root config** (`environments/dev`, `environments/prod`) always computes `name_prefix` as `{project}-{environment}-{capability}` — it's the one choosing which module to call, so it's the one that knows the capability.
- When one module composes another internally (`data-platform` calling `storage-s3`, or a compute module calling `iam`), the nested module inherits the **caller's** identity rather than computing its own — e.g. a role created on behalf of `compute-ecs` is grouped under the `ecs` capability, not `iam`. That way everything belonging to one workload is easy to find together.

Tagging works differently from naming. `Project`, `Environment`, `Owner`, and `ManagedBy` are applied automatically via each environment's `default_tags` provider setting — no module or consumer sets them by hand. `Capability` and `Purpose` are deliberately **not** separate tags: `default_tags` is one fixed map per environment, so it can't vary per module call. That identity is captured in the resource name instead, which is why the naming convention above carries real information rather than being cosmetic.

## Environments and free-tier strategy

`dev` and `prod` are separate root configs, each with its own Terraform state (same S3 bucket, different state key) — a mistake in one can never touch the other. Both call **identical module code**; only input values differ.

This project runs on a free-tier AWS account, which directly shaped several defaults:

| Feature | Free-tier coverage | Approach taken |
| --- | --- | --- |
| NAT Gateway | None at all | Off by default; one shared gateway (not per-AZ) if ever turned on |
| RDS Multi-AZ | Not covered | Off by default |
| RDS / EC2 instance hours | 750 hrs/month, smallest instance class | Same smallest class in both environments; avoid running both simultaneously for long periods |
| ECS Fargate | No free tier at all | Avoided entirely — `compute-ecs` uses the EC2 launch type instead |
| S3, IAM, Glue Catalog, Athena (small data) | Free or negligible | No real constraint |

For the genuinely paid features (Multi-AZ, per-AZ NAT), the module still supports them fully as variables — they're proven with a temporary `apply`, confirmed working, then `destroy`, rather than left running continuously.

## Consumer example and expected outputs

`environments/dev` (and identically, `environments/prod`) composes five capabilities into one realistic stack: a network, a containerised web app, a private database, a raw-data bucket, and an analytics layer over that data.

```hcl
module "networking" {
  source = "../../modules/networking"
  name_prefix = "${var.project}-${var.environment}-net"
  enable_nat_gateway = false
}

module "webapp" {
  source = "../../modules/compute-ecs"
  name_prefix = "${var.project}-${var.environment}-ecs"
  purpose = "webapp"
  vpc_id = module.networking.vpc_id
  subnet_ids = module.networking.public_subnet_ids
  instance_type = "t3.micro"
  min_size = 1
  max_size = 1
  desired_capacity = 1
  container_image = "public.ecr.aws/nginx/nginx:latest"
  container_port = 80
  allowed_ingress_cidr = "0.0.0.0/0"
}

module "database" {
  source = "../../modules/database-rds"
  name_prefix = "${var.project}-${var.environment}-rds"
  purpose = "webapp"
  vpc_id = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids
  app_security_group_id = module.webapp.instance_security_group_id
}

module "raw_data" {
  source = "../../modules/storage-s3"
  name_prefix = "${var.project}-${var.environment}-s3"
  purpose = "raw-data"
  data_classification = "internal"
}

module "analytics" {
  source = "../../modules/data-platform"
  name_prefix = "${var.project}-${var.environment}-data"
  purpose = "orders"
  source_bucket_arn = module.raw_data.bucket_arn
  source_bucket_name = module.raw_data.bucket_name
  source_prefix = "orders/"
}
```

### Expected outputs

Running `terraform output` after `apply` should return:

| Output | What it tells you |
| --- | --- |
| `vpc_id` | The provisioned VPC |
| `ecs_cluster_name`, `ecs_service_name` | Where to find the running web app |
| `db_endpoint` | The RDS connection endpoint (reachable only from inside the VPC) |
| `db_credentials_secret_arn` | Where the generated DB credentials live in Secrets Manager |
| `raw_data_bucket_name` | The bucket the analytics pipeline reads from |
| `glue_database_name`, `athena_workgroup_name` | Where to run SQL queries against the raw data |

### Proof of deployment

Screenshots of `terraform plan` and `terraform apply` for each capability, and the functional tests that prove each one actually works end to end (not just that Terraform reported success):

**Networking**
`![networking plan](screenshots/networking-plan.png)`
`![networking apply](screenshots/networking-apply.png)`

**IAM** — standalone validation test proving the least-privilege guardrail rejects a wildcard, then a real role created and destroyed
`![iam guardrail rejection](screenshots/iam-validation-error.png)`
`![iam role created](screenshots/iam-apply.png)`

**Compute (webapp)** — apply output, then the functional test: `curl` against the instance's public IP returning the nginx welcome page
`![compute-ecs apply](screenshots/compute-ecs-apply.png)`
`![curl test result](screenshots/webapp-curl-test.png)`

**Database** — apply output, then a successful connection made *from inside* the VPC (proving it is genuinely not publicly reachable)
`![database-rds apply](screenshots/database-apply.png)`

**Storage & Data Platform** — apply output, then the crawler run and an Athena query returning real rows from the sample data
`![storage and data-platform apply](screenshots/data-platform-apply.png)`
`![athena query results](screenshots/athena-query-results.png)`

## Security considerations

- No S3 bucket or RDS instance is ever publicly reachable — hardcoded in the modules, not a configurable option.
- Every S3 bucket is encrypted and versioned by default; lifecycle rules bound both current and old-version storage growth.
- The database is reachable only from a named application security group — not an IP range.
- Database credentials live in Secrets Manager, never as a plain Terraform variable (state-file exposure is a documented caveat above, not silently ignored).
- The `modules/iam` guardrail physically rejects wildcard resource ARNs at `plan` time.
- The VPC's default security group is deliberately stripped of every rule.
- VPC flow logs and CloudWatch logging are on by default across networking and compute.
- Every AWS-service-facing role (VPC flow logs, ECS container instances, the Glue crawler) is scoped narrowly to exactly what that one function needs — never a shared, broad role.

## Architecture

`![COB architecture](docs/architecture-diagram.png)`.

The diagram groups infrastructure into two independent stacks — an application stack (networking, compute, database) and a data stack (storage, Glue, Athena) — with IAM shown as the cross-cutting component providing scoped access into both, rather than as a single generic role.

## Architectural decisions and trade-offs

| Decision | Reasoning |
| --- | --- |
| EC2 launch type over Fargate for `compute-ecs` | Fargate has no free-tier coverage at all; EC2 draws from the account's 750 free hours/month |
| Single S3 bucket for state, split by key, native S3 locking | Avoids a second AWS resource (DynamoDB) purely for locking, given the Terraform version in use |
| NAT gateway and RDS Multi-AZ off by default | Both are billed continuously with no free-tier coverage; proven via a one-time apply-then-destroy rather than left running |
| Capability-specific IAM roles built inline (flow logs, ECS container instances, Glue crawler) | These are infrastructure plumbing for an AWS *service*, not a workload identity — kept out of the general-purpose `modules/iam`, which is reserved for applications |
| RDS security group references the app's security group, not a CIDR | Much stronger isolation — nothing can reach the database except the specific compute resource, regardless of network |
| `storage-s3` generates its own unique bucket-name suffix | Removes AWS's global-uniqueness constraint from the consumer entirely, rather than making them solve it |
| `data-platform` composes `storage-s3` for its Athena results bucket | Proves genuine module reusability — the platform consumes its own capabilities the same way an external team would |
| `examples/` left empty, pointing to `environments/` | `dev` and `prod` already are realistic, working example consumers; a third duplicate copy would just be unmaintained duplicate code |

## Assumptions

- Single AWS account, single region (`eu-north-1`), for both environments.
- The AWS account is free-tier or early-stage — cost-aware defaults (NAT off, Multi-AZ off, EC2 over Fargate) were chosen deliberately on that basis.
- Terraform ≥ 1.9 (≥ 1.10 to use native S3 state locking as configured) and AWS provider `~> 6.0`.
- One engineer/small team operating the platform at a time — no multi-team concurrent-apply tooling beyond Terraform's own state locking.

## Known limitations

- RDS uses the AWS default parameter group; a custom one is out of scope for v1.
- Long generated resource names are not automatically truncated or hashed against AWS length limits — untested beyond this project's short prefixes.
- `compute-ecs` (EC2 launch type) maps a fixed host port in bridge networking mode, so only one task can run per EC2 instance at a time.
- Each capability's narrower out-of-scope items (no VPN/Transit Gateway, no cross-account IAM, no read replicas, no Lake Formation, etc.) are listed alongside that capability under [Capability details](#capability-details) above.

## Getting started

1. Create and lock down the one-time Terraform state bucket (versioned, encrypted, public access blocked).
2. `cd environments/dev && terraform init`.
3. `terraform plan`, review it against the expected resource list, then `terraform apply`.
4. Repeat for `environments/prod` — same commands, same modules, different values.
