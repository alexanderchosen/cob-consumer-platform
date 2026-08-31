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
- **Key inputs:** `name_prefix`, `purpose`, `trusted_service` (`ecs-tasks`/`ec2`), `s3_read_arn`, `s3_write_arn`, `secrets_read_arn`
- **Key outputs:** `role_arn`, `role_name`, `instance_profile_name`
- **Secure by default:** a validation block physically rejects a wildcard (`"*"`) resource ARN at `plan` time — least privilege is enforced in code, not left as a guideline.
- **Out of scope (v1):** federated/SSO roles, cross-account access.

#### Object storage — `modules/storage-s3`

- **The ask:** give a team somewhere safe to put data, matched to how sensitive it is.
- **Key inputs:** `name_prefix`, `purpose`, `data_classification` (`public`/`internal`), `lifecycle_days`, `enable_versioning`
- **Key outputs:** `bucket_id`, `bucket_arn`, `bucket_name`, `kms_key_arn`
- **Secure by default:** public access is blocked unconditionally (not a variable); encryption is always on; a lifecycle rule expires both current *and* old object versions, so cost doesn't grow unbounded.
- **Trade-off:** S3 bucket names must be globally unique across all of AWS, so the module appends a random suffix itself — the consumer never has to solve AWS's uniqueness problem by hand.
- **Cost note:** `data_classification = "sensitive"` creates a dedicated KMS key at a flat **$1/month regardless of use** — use `"internal"` or `"public"` unless you specifically need it.
- **Out of scope (v1):** cross-region replication, static website hosting.

#### Compute — `modules/compute-ec2`, `modules/compute-ecs`

- **The ask:** run an application, correctly networked and permissioned, without wiring subnets/security groups/IAM roles by hand.
- **Key inputs:** `name_prefix`, `purpose`, `vpc_id`, `subnet_ids`, `container_image`/`container_port` (ECS), `instance_type`, `min_size`/`max_size`/`desired_capacity`, `allowed_ingress_cidr`, and `s3_read_arn`/`s3_write_arn`/`secrets_read_arn` which are passed straight through to the workload's IAM role.
- **Key outputs:** `cluster_name`, `service_name`, `instance_security_group_id`, `task_role_arn`
- **Trade-off:** `compute-ecs` uses the **EC2 launch type** (a launch template, an Auto Scaling Group, and an ECS capacity provider) instead of Fargate.
- **Limitation:** the container's port maps to a fixed host port in `bridge` networking mode, so only one task can run per EC2 instance at a time.
- **Out of scope (v1):** auto-scaling policies, blue/green deployment.

#### Relational database — `modules/database-rds`

- **The ask:** a managed database a team doesn't have to think about backups or placement for.
- **Key inputs:** `name_prefix`, `purpose`, `vpc_id`, `subnet_ids`, `app_security_group_id`, `engine`, `engine_version`, `size_tier`, `multi_az`, `backup_retention_days`, `deletion_protection`
- **Key outputs:** `db_endpoint`, `db_port`, `credentials_secret_arn`
- **Secure by default:** never publicly accessible and always encrypted — both hardcoded, not variables.
- **Trade-off:** the database's security group allows traffic only from a *named application security group*, not an IP range — a much stronger form of isolation, at the cost of the consumer having to pass in that security group ID explicitly.
- **Cost note:** Multi-AZ isn't free-tier eligible, so it defaults to `false`.
- **Out of scope (v1):** read replicas, cross-region DR, a custom parameter group (uses the AWS default).

#### Data platform — `modules/data-platform`

- **The ask:** let analysts query data already sitting in S3, using SQL, without per-dataset manual setup.
- **Key inputs:** `name_prefix`, `purpose`, `source_bucket_arn`, `source_bucket_name`, `source_prefix`, `crawler_schedule`
- **Key outputs:** `glue_database_name`, `athena_workgroup_name`, `crawler_name`, `results_bucket_name`
- **Secure by default:** Athena query results are always encrypted; the crawler's IAM role can only ever read the one S3 prefix it's told to crawl, never the whole bucket.
- **Trade-off:** this module composes `modules/storage-s3` internally for its own Athena results bucket, rather than reimplementing bucket logic — proof the platform reuses its own capabilities the same way an external team would.
- **Out of scope (v1):** Lake Formation fine-grained permissions, cross-account catalog sharing.

```
resource "aws_s3_object" "test_orders" {
  bucket = module.raw_data.bucket_name
  key = "orders/orders.csv"
  source = "${path.module}/../../docs/test_data/orders.csv"
  etag = filemd5("${path.module}/../../docs/test_data/orders.csv")
}
```

Each environment uses the s3 resource above to upload data a file to the s3 bucket, which is then used by the data-platform to produce queries and results.

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
module "database" {
  source = "../../modules/database-rds"
  name_prefix = "${var.project}-${var.environment}-rds"
  purpose = "webapp"
  vpc_id = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids
  app_security_group_id = module.my_app.instance_sg_id
}
```

Declaring the owner, and purpose of the database, and properly setting up the VPC, subnet and security group by running the networking module produce a fully working database with a unique name alongside other components without having to understand the backend of the module. Every security decision, gateway type, type of subnet used is made by the interconnected modules, not the consumer.

```hcl
module "raw_data" {
  source = "../../modules/s3"
  name_prefix = "${var.project}-${var.environment}-s3"
  purpose = "raw-data"
  data_classification = "internal"
}
```

Two lines of intent (`purpose`, `data_classification`) produce a fully encrypted, versioned, lifecycle-managed, public-access-blocked s3 bucket — every security decision is made by the module, not the consumer.

```hcl
module "analytics" {
  source = "../../modules/data-platform"
  name_prefix = "${var.project}-${var.environment}-data"
  purpose = "orders"
  source_bucket_arn = module.raw_data.bucket_arn
  source_bucket_name = module.raw_data.bucket_name
  source_prefix = "orders/"
}
```

The consumer provides the owner, name of the data platform, purpose of the data platform, and source_prefix to produce fully interconnected services from s3 bucket with an uploaded file, Glue with catalog and database, athena for querying the table and saving the results in another s3 bucket. It also relies heavily on a granular level IAM roles and policy for security and access control. All these are taken care of by the module backend, not the consumer

## Naming and tagging

Every resource follows **`{project}-{environment}-{resource_type}-{purpose}`** — e.g. `cob-prod-s3-uploads`. Two rules make this consistent everywhere:

- The **environment root config** (`environments/dev`, `environments/prod`) always computes `name_prefix` as `{project}-{environment}-{capability}` — it's the one choosing which module to call, so it's the one that knows the capability.
- When one module composes another internally (`data-platform` calling `storage-s3`, or a compute module calling `iam`), the nested module inherits the **caller's** identity rather than computing its own — e.g. a role created on behalf of `compute-ecs` is grouped under the `ecs` capability, not `iam`. That way everything belonging to one workload is easy to find together.

Tagging works differently from naming. `Project`, `Environment`, `Owner` are applied automatically via each environment's `default_tags` provider setting — no module or consumer sets them by hand. `Resource_type` and `Purpose` are deliberately **not** separate tags: `default_tags` is one fixed map per environment, so it can't vary per module call. That identity is captured in the resource name instead, which is why the naming convention above carries real information.

## Environments and free-tier strategy

`dev` and `prod` are separate root configs, each with its own Terraform state (same S3 bucket, different state key) — a mistake in one can never touch the other. Both call **identical module code**; only input values differ.

This project runs on a free-tier AWS account.

- Single AWS account, single region (`eu-north-1`), for both environments.
- The AWS account is free-tier or early-stage — cost-aware defaults (NAT off, Multi-AZ off, EC2 over Fargate) were chosen deliberately on that basis.
- Terraform ≥ 1.9 (≥ 1.10 to use native S3 state locking as configured) and AWS provider `~> 6.0`.
- One engineer/small team operating the platform at a time — no multi-team concurrent-apply tooling beyond Terraform's own state locking.

## Environment and its modules

Both environments (`environments/dev` and identically, `environments/prod`) composes five capabilities into one realistic stack: a network, a containerised web app, a private database, a raw-data bucket, and an analytics layer over that data.

This sample uses the DEV environment:

```hcl
module "networking" {
  source = "../../modules/networking"
  name_prefix = "${var.project}-${var.environment}-net"
  enable_nat_gateway = false
}

module "my_app" {
  source = "../../modules/ecs"
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
  source = "../../modules/rds"
  name_prefix = "${var.project}-${var.environment}-rds"
  purpose = "webapp"
  vpc_id = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids
  app_security_group_id = module.my_app.instance_sg_id
}

module "raw_data" {
  source = "../../modules/s3"
  name_prefix = "${var.project}-${var.environment}-s3"
  purpose = "raw-data"
  data_classification = "internal"
}

resource "aws_s3_object" "test_orders" {
  bucket = module.raw_data.bucket_name
  key = "orders/orders.csv"
  source = "${path.module}/../../docs/test_data/orders.csv"
  etag = filemd5("${path.module}/../../docs/test_data/orders.csv")
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

Running `terraform output` after `terrform plan` and `terraform apply` should return:

| Output | What it tells you |
| --- | --- |
| `vpc_id` | The provisioned VPC |
| `ecs_cluster_name`, `ecs_service_name` | Where to find the running web app |
| `db_endpoint` | The RDS connection endpoint (reachable only from inside the VPC) |
| `db_credentials_secret_arn` | Where the generated DB credentials live in Secrets Manager |
| `raw_data_bucket_name` | The bucket the analytics pipeline reads from |
| `glue_database_name`, `athena_workgroup_name` | Where to run SQL queries against the raw data |

## Consumer example and expected outputs

We have 2 consumer examples; which are the Application Engineering and Data engineering team

**Application Engineering**

This consumer composes of three capabilities into one realistic stack: a network, a containerised web app, and a private database.
This team owns "Web applications, Microservices" — nothing about data, nothing about analytics. So their whole world is three module calls: a network to run in, somewhere to run the container, and a database behind it.

```hcl
module "networking" {
  source = "../../modules/networking"
  name_prefix = "${var.project}-${var.environment}-net"
  enable_nat_gateway = false
}

module "webapp" {
  source = "../../modules/ecs"
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
  source = "../../modules/rds"
  name_prefix = "${var.project}-${var.environment}-rds"
  purpose = "webapp"
  vpc_id = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids
  app_security_group_id  = module.webapp.instance_sg_id
}

```

**Data Engineering**

this team owns "Data ingestion, Data processing, Analytics" — that's storage-s3 (where ingested data lands) and data-platform (the crawler, catalog, and Athena workgroup that turn raw files into something queryable). No networking, no compute, no database — Glue, Athena, and S3 are regional services, never VPC-scoped.

```hcl
module "raw_data" {
  source = "../../modules/storage-s3"
  name_prefix  = "${var.project}-${var.environment}-s3"
  purpose = "raw-data"
  data_classification = "internal"
}

resource "aws_s3_object" "students" {
  bucket = module.raw_data.bucket_name
  key = "school/class/student.csv"
  source = "${path.module}/../../docs/test_data/student.csv"
  etag = filemd5("${path.module}/../../docs/test_data/student.csv")
}

module "analytics" {
  source = "../../modules/data-platform"
  name_prefix = "${var.project}-${var.environment}-data"
  purpose = "class-register"
  source_bucket_arn = module.raw_data.bucket_arn
  source_bucket_name = module.raw_data.bucket_name
  source_prefix = "class/"
}
```

### Proof of deployment

Screenshots of `terraform plan` and `terraform apply` for each capability, and the functional tests that prove each one actually works end-to-end (not just that Terraform reported success):

#### Networking Module


<img width="1807" height="1022" alt="iam_terraform_plan" src="https://github.com/user-attachments/assets/bdb6958b-fa92-461b-aed5-4adfbb911333" />

**Networking Plan Output**


<img width="796" height="680" alt="terraform-apply-networking" src="https://github.com/user-attachments/assets/0dce989e-bedf-4c91-845b-a47b78227e1b" />

**Networking Apply Output**


<img width="797" height="525" alt="terraform_validate-for-networking-dev" src="https://github.com/user-attachments/assets/dd224c79-3fbb-41d6-98e0-635ce5e6807a" />

**Networking Validate Output**


<img width="1807" height="1022" alt="iam_terraform_plan" src="https://github.com/user-attachments/assets/7654208a-192a-458f-9ef9-fa5d29ff7544" />

**IAM Terraform Plan Output**


<img width="1920" height="1020" alt="iam_terraform-apply" src="https://github.com/user-attachments/assets/497e8e01-1609-4457-8fbc-d795628d7e16" />

**IAM Terraform Apply**



#### IAM — standalone validation test proving the least-privilege guardrail rejects a wildcard, then a real role created and destroyed



<img width="1920" height="1020" alt="iam_wildcard_error" src="https://github.com/user-attachments/assets/d2e6ae48-a5e9-4a37-b226-5d2411e27e8f" />

**IAM Wildcard Error**


<img width="1920" height="1020" alt="Iam_role_created_inline" src="https://github.com/user-attachments/assets/84abff32-c59c-498f-837f-234606d25223" />

**IAM role_created**


<img width="1920" height="1020" alt="iam_role_policy_created" src="https://github.com/user-attachments/assets/7fb5b5ee-9632-4a6c-8663-24e59b4363ac" />

**IAM Role Policy**


<img width="1920" height="1020" alt="iam-terraform-show" src="https://github.com/user-attachments/assets/9d700991-47f4-4933-8873-873728cba73f" />

**IAM**


#### Compute (webapp) — showing terraform plan, apply, and AWS outputs via Console


<img width="1920" height="1020" alt="ecs-terraform-apply" src="https://github.com/user-attachments/assets/5ce863fc-66a2-4305-ade6-36ef1fd43b2b" />

**ECS Apply**


<img width="1920" height="1020" alt="ecs-terraform-plan" src="https://github.com/user-attachments/assets/c476174d-b8d6-4c4d-aa09-e2fcc216bd05" />

**ECS plan**


<img width="1920" height="1020" alt="ecs-terraform-plan1" src="https://github.com/user-attachments/assets/e906db09-62d3-48a9-bd19-361f46e94026" />

**ECS Plan**


<img width="1920" height="1020" alt="ec2-ecs-instance-aws" src="https://github.com/user-attachments/assets/2dba2fc7-ac2e-43c1-8520-a8f74af8b7bf" />

**EC2 Instance Created**


<img width="1920" height="1020" alt="ecs-cluster-aws" src="https://github.com/user-attachments/assets/627a4c5c-99ae-4bcd-82f4-1b4e1cf5623d" />

**ECS Cluster**


<img width="1920" height="1020" alt="ecs-task-def-aws" src="https://github.com/user-attachments/assets/039495b2-b3dd-41f7-a7e4-6cd63a6640c9" />

**ECS Task Definition**


<img width="801" height="567" alt="private-subnet-1" src="https://github.com/user-attachments/assets/32d784c5-c461-4248-b4fc-dee59a1802a5" />

**Private Subnet**


<img width="801" height="692" alt="public-subnet-0" src="https://github.com/user-attachments/assets/a92cc29a-2dce-443e-b250-df82d7567072" />

**Athena Terraform Plan Output**


##### Database — apply output, then a successful connection made *from inside* the VPC (proving it is genuinely not publicly reachable)


<img width="1920" height="1020" alt="rds-apply" src="https://github.com/user-attachments/assets/b0f1057f-3507-4bf1-a973-75a70258f66a" />

**RDS Terraform Apply**


<img width="1920" height="1020" alt="rds-plan" src="https://github.com/user-attachments/assets/4aeb86a4-f1a6-4da4-abba-c3854ba95e8a" />

**RDS Terraform Plan**


<img width="1920" height="1020" alt="rds-db-aws" src="https://github.com/user-attachments/assets/b5dddc94-1f6f-407b-9b5c-8718095d5dcc" />

**RDS database in AWS**


<img width="1920" height="1020" alt="rds_snapshot_aws" src="https://github.com/user-attachments/assets/37ed8b2f-d0d4-4527-bfec-42639edf2d8a" />

**RDS Snapshot in AWS**


#### Storage & Data Platform — apply output, then the crawler run and an Athena query returning real rows from the sample data


<img width="1920" height="1020" alt="s3_athena_dev_plan" src="https://github.com/user-attachments/assets/1c307bf2-163a-4250-8be8-27730f1c548f" />

**Athena Terraform Plan**


<img width="1920" height="1020" alt="crawlers_glue" src="https://github.com/user-attachments/assets/c3464581-d239-464a-9f93-bb119ce9f2ac" />

**Crawler Glue**


<img width="1920" height="1020" alt="s3_athena_raw_data-dev" src="https://github.com/user-attachments/assets/a36c0153-5ca1-4690-9659-69ed934a9f72" />

**Athena s3 raw data**



<img width="1920" height="1020" alt="s3_athena_glue_dev" src="https://github.com/user-attachments/assets/d64287b0-dc8d-409e-aed6-85f0fa74dce8" />

**Athena Glue Interface**


<img width="1920" height="1020" alt="table_glue" src="https://github.com/user-attachments/assets/6d18135f-29a5-41d2-9ff4-780b40d1b77d" />

**Athena Glue Table**


<img width="1920" height="1020" alt="athena_table_orders" src="https://github.com/user-attachments/assets/371bfcbd-96a2-47ab-949f-c0534d2c7835" />

**Athena Table showing Orders**


<img width="1920" height="1020" alt="athena_orders_query" src="https://github.com/user-attachments/assets/d7f44b4b-7f5d-4623-b893-3f28b63be68c" />

**Athena Query Results**


#### Applying Terraform Destroy


<img width="1920" height="1020" alt="terraform-destroy-module-database" src="https://github.com/user-attachments/assets/341122f8-080e-4f6e-9068-4b57a1c4cd26" />

**Terraform Destroy on Database Module**


<img width="1920" height="1020" alt="terraform-destroy-module-my_app" src="https://github.com/user-attachments/assets/2aaee958-d88a-48e4-ad5d-77f93b390660" />

**Terraform Destroy on My_App Module**



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


<img width="562" height="562" alt="terraform_arch drawio" src="https://github.com/user-attachments/assets/a9390df0-2fff-4af3-9472-020ad84a08dc" />

**Architecture for the COB Project**

The diagram groups infrastructure into two independent stacks — an application stack (networking, compute, database) and a data stack (storage, Glue, Athena) — with IAM shown as the cross-cutting component providing scoped access into both, rather than as a single generic role.

The two arrows are the only relationships drawn, and both are real, specific ones from the actual Terraform: EC2 → RDS is the security-group-to-security-group trust. The database can only be reached from the app's security group, nothing else.
The S3 → Glue → Athena chain is literally the pipeline order to upload files, create catalog, crawl them and save the queries and result.

This diagram is the same for all environment, since both environments call identical module code, the shape of the architecture never changes between them; only sizing and some internal details would differ.

## Architectural decisions and trade-offs

| Decision | Reasoning |
| --- | --- |
| EC2 launch type over Fargate for `compute-ecs` | Fargate has no free-tier coverage at all; EC2 draws from the account's 750 free hours/month |
| Single S3 bucket for state, split by key, native S3 locking | Avoids a second AWS resource (DynamoDB) purely for locking, given the Terraform version in use |
| NAT gateway and RDS Multi-AZ off by default | Both are billed continuously with no free-tier coverage; proven via a one-time apply-then-destroy rather than left running |
| Capability-specific IAM roles built inline (flow logs, ECS container instances, Glue crawler) | These are infrastructure plumbing for an AWS *service*, not a workload identity — kept out of the general-purpose `modules/iam`, which is reserved for applications |
| RDS security group references the app's security group, not a CIDR | Much stronger isolation — nothing can reach the database except the specific compute resource, regardless of network |
| `storage-s3` generates its own unique bucket-name suffix | Removes AWS's global-uniqueness constraint from the consumer entirely, rather than making them solve it |
| `data-platform` composes `s3` for its Athena results bucket | Proves genuine module reusability — the platform consumes its own capabilities the same way an external team would |

## Known limitations

- RDS uses the AWS default parameter group; a custom one is out of scope for v1.
- Long generated resource names are not automatically truncated or hashed against AWS length limits — untested beyond this project's short prefixes.
- `ecs` (EC2 launch type) maps a fixed host port in bridge networking mode, so only one task can run per EC2 instance at a time.
- Each capability's narrower out-of-scope items (no VPN/Transit Gateway, no cross-account IAM, no read replicas, no Lake Formation.)

## Getting started

Follow the steps below accordingly:

1. Create and lock down the one-time Terraform state bucket (versioned, encrypted, public access blocked).
 A. Choose a globally unique s3 bucket name
 B. run the following to configure the bucket, replace bucket name where needed:

 `aws s3api create-bucket --bucket YOUR-BUCKET-NAME --region eu-north-1 --create-bucket-configuration LocationConstraint=eu-north-1`

 `aws s3api put-bucket-versioning --bucket YOUR-BUCKET-NAME --versioning-configuration Status=Enabled`

`aws s3api put-bucket-encryption --bucket YOUR-BUCKET-NAME --server-side-encryption-configuration '{"Rules" [{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'`

`aws s3api put-public-access-block --bucket YOUR-BUCKET-NAME --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true`

1. run this in both environment: `cd environments/<environment-name> && terraform init`.

2. `terraform plan`, review it against the expected resource list, then `terraform apply`.
