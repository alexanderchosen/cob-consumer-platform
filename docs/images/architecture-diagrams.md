# COB 2 — Architecture Diagrams

Two diagrams. The first shows how a change travels from a pull request to
provisioned infrastructure, and where it is stopped. The second shows what
the pipeline actually builds and which COB module provisioned each piece.

---

## Diagram 1 — Delivery pipeline and trust boundaries

```mermaid
flowchart TD
    classDef repo      fill:#1e293b,stroke:#60a5fa,stroke-width:2px,color:#e2e8f0
    classDef nocreds   fill:#064e3b,stroke:#34d399,stroke-width:2px,color:#d1fae5
    classDef needcreds fill:#1e3a8a,stroke:#93c5fd,stroke-width:2px,color:#dbeafe
    classDef gate      fill:#7c2d12,stroke:#fb923c,stroke-width:3px,color:#ffedd5
    classDef iam       fill:#713f12,stroke:#fbbf24,stroke-width:2px,color:#fef3c7
    classDef infra     fill:#312e81,stroke:#a5b4fc,stroke-width:2px,color:#e0e7ff

    subgraph SRC["SOURCE — two repositories"]
        direction LR
        MOD[("cob-modules-platform<br/>networking · iam · s3 · ec2<br/>ecs · rds · data-platform<br/><b>released as tag v1.0.0</b>")]
        CON[("cob-consumer-platform<br/>environments/dev<br/>environments/prod<br/>examples/consumers")]
        MOD ==>|"source = git::…//modules/NAME?ref=v1.0.0<br/>a version bump is a reviewed code change"| CON
    end

    CON --> PR

    subgraph CI["PULL REQUEST — continuous integration"]
        direction TB
        PR[/"Pull request opened<br/>targeting main"/]
        FMT["terraform fmt -check<br/>repo-wide"]
        VAL["terraform validate<br/>dev · prod · examples<br/>init -backend=false"]
        PD["terraform plan — dev<br/>-lock=false"]
        PP["terraform plan — prod<br/>-lock=false"]
        CMT[/"Plan published as a<br/>pull request comment"/]

        PR --> FMT --> VAL
        VAL --> PD
        VAL --> PP
        PD --> CMT
        PP --> CMT
    end

    CMT --> L1

    L1{{"LOCK 1 — BRANCH PROTECTION<br/>6 required status checks<br/>no direct push to main<br/>branch must be up to date<br/><br/>stale approvals dismissed.<br/> 1 approving review from a second person. "}}

    L1 -->|"all checks green"| MERGE[/"Merge to main"/]
    L1 -.->|"any check red<br/>merge button disabled"| STOP1>"CHANGE BLOCKED"]

    MERGE --> AD

    subgraph CD["MERGE TO MAIN — continuous delivery"]
        direction TB
        AD["apply dev<br/>environment: dev<br/>auto-applies"]
        PPR["plan prod<br/>published to run summary<br/>for the reviewer"]
        L2{{"LOCK 2 — ENVIRONMENT APPROVAL<br/>required reviewer<br/>deployment branch: main only<br/>job cannot start until approved"}}
        AP["apply prod<br/>environment: prod"]

        AD -->|"dev succeeded"| PPR --> L2
        L2 -->|"human approves<br/>against a visible plan"| AP
        L2 -.->|"not approved"| STOP2>"DEPLOYMENT BLOCKED"]
    end

    subgraph AWS["AWS — account 324404179878, eu-north-1"]
        direction TB
        OIDC[("OIDC identity provider<br/>token.actions.githubusercontent.com<br/>audience: sts.amazonaws.com")]
        RPLAN["cob-oidc-plan<br/><b>ReadOnlyAccess</b>"]
        RAPPLY["cob-oidc-apply<br/><b>AdministratorAccess</b>"]
        STATE[("Terraform state bucket<br/>versioned · encrypted<br/>public access blocked<br/>data-platform/dev · data-platform/prod")]
        DEVI["dev data platform"]
        PRODI["prod data platform"]

        OIDC --> RPLAN
        OIDC --> RAPPLY
        RAPPLY --> DEVI
        RAPPLY --> PRODI
        RPLAN -.->|"read"| STATE
        RAPPLY -->|"read + write + lock"| STATE
    end

    PD -.->|"sub: repo:alexanderchosen@56475753/cob-consumer-platform@1440746664:*"| RPLAN
    PP -.->|"same read-only role"| RPLAN
    PPR -.->|"read-only"| RPLAN
    AD ==>|"sub: …:environment:dev"| RAPPLY
    AP ==>|"sub: …:environment:prod"| RAPPLY

    L3{{"LOCK 3 — AWS TRUST POLICY<br/>apply role requires environment:dev or environment:prod<br/>in the OIDC subject claim. GitHub issues that claim only to a<br/>job declaring the environment, and such a job cannot start<br/>until approved. Approval is a precondition for credentials."}}
    L3 -.-> RAPPLY

    class MOD,CON repo
    class FMT,VAL nocreds
    class PD,PP,PPR,AD,AP needcreds
    class L1,L2,L3 gate
    class OIDC,RPLAN,RAPPLY iam
    class STATE,DEVI,PRODI infra
```

**Reading the diagram**

- **Green jobs need no AWS credentials at all.** `fmt` and `validate` run with
  `init -backend=false`, so a syntax error fails in about 20 seconds without a
  single cloud API call.
- **The dotted credential arrows carry the actual OIDC subject claims.** The
  plan jobs match a wildcard subject; the apply jobs match an exact
  `environment:` subject. That difference is Lock 3.
- **The three locks are independent.** Removing any one leaves the others
  standing.

---

## Diagram 2 — Provisioned data platform

Identical in shape for `dev` and `prod`; only input values and state keys differ.

```mermaid
flowchart TD
    classDef cobmod  fill:#1e3a8a,stroke:#93c5fd,stroke-width:2px,color:#dbeafe
    classDef consumer fill:#064e3b,stroke:#34d399,stroke-width:2px,color:#d1fae5
    classDef catalog fill:#312e81,stroke:#a5b4fc,stroke-width:2px,color:#e0e7ff
    classDef iam     fill:#713f12,stroke:#fbbf24,stroke-width:2px,color:#fef3c7

    subgraph LAKE["LANDING ZONE"]
        BUCKET[("S3 lake bucket<br/><b>COB: modules/s3</b><br/>encrypted · versioned<br/>public access blocked<br/>lifecycle 30d dev / 365d prod<br/>globally unique name suffix")]
        SEED[/"raw/orders/orders.csv<br/>raw/customers/customers.csv<br/>raw/products/products.csv<br/><b>consumer data, not platform</b><br/>aws_s3_object"/]
        SEED -->|"uploaded into"| BUCKET
    end

    subgraph CATALOGUE["CATALOGUE AND QUERY"]
        CRAWL["Glue crawler<br/><b>COB: modules/data-platform</b><br/>source_prefix = raw/<br/>one table per sub-prefix"]
        CROLE["Crawler IAM role<br/>scoped to the raw/ prefix only<br/>never the whole bucket"]
        GLUE[("Glue Data Catalog<br/>orders · customers · products")]
        WG["Athena workgroup<br/>results always encrypted<br/>workgroup config enforced"]
        RESULTS[("Athena results bucket<br/><b>COB: modules/s3</b><br/>composed by data-platform<br/>the platform reusing itself")]

        CRAWL --> GLUE --> WG --> RESULTS
        CROLE -.->|"assumed by"| CRAWL
    end

    BUCKET ==>|"crawled"| CRAWL
    WG ==>|"SQL across all three tables"| OUT[/"Revenue by customer segment<br/>and product category"/]

    class BUCKET,CRAWL,WG,RESULTS cobmod
    class SEED,OUT consumer
    class GLUE catalog
    class CROLE iam
```

**Reading the diagram**

- **Every box is tagged with the COB module that provisioned it.** Nothing in
  the data platform was hand-built around the platform.
- **The seed objects are deliberately not a COB capability.** COB provisions
  the bucket; what the consumer puts in it is application data. A platform
  module that uploaded these CSVs would be a platform that knows about this
  team's datasets.
- **The results bucket is `data-platform` calling `s3` internally** — the
  platform consuming its own capability the same way an external team does.

---

## Optional — Diagram 3, environment isolation

Small, and it answers "how do you know dev cannot damage prod?" at a glance.

```mermaid
flowchart LR
    classDef env   fill:#1e3a8a,stroke:#93c5fd,stroke-width:2px,color:#dbeafe
    classDef state fill:#312e81,stroke:#a5b4fc,stroke-width:2px,color:#e0e7ff

    subgraph D["environments/dev"]
        DC["identical module code<br/>environment = dev<br/>lifecycle_days = 30<br/>crawler 03:00 UTC"]
    end

    subgraph P["environments/prod"]
        PC["identical module code<br/>environment = prod<br/>lifecycle_days = 365<br/>crawler 02:00 UTC"]
    end

    SB[("Terraform state bucket<br/>versioned · encrypted")]

    DC -->|"key = data-platform/dev/terraform.tfstate"| SB
    PC -->|"key = data-platform/prod/terraform.tfstate"| SB

    class DC,PC env
    class SB state
```

Separate directories, separate state keys, one bucket. The backend block cannot
use variables, so the key is a literal per directory — which is precisely why
directories were chosen over workspaces for environment separation.
