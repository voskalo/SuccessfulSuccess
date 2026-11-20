# ADR 0008: Run the core of the app on Google Cloud as well

- Status: Accepted
- Date: 2026-11-20

## Context

The app runs on AWS: a static Next.js export on S3 behind CloudFront, the FastAPI
backend on Lambda behind a function URL, and PostgreSQL on RDS (`db.t3.micro`,
running around the clock). Sign-in (Cognito), the weekly report (EventBridge, SQS,
Lambda, S3, SES) and the agenda parser (Lambda and Bedrock) are Terraform in
`infra/` since [ADR 0007](0007-terraform.md).

Lab 9 asks what it takes to run the same system on Google Cloud and what it would
cost. The part that makes the app usable is the frontend, the API and the
database; the rest can stay on AWS for now.

## Decision

Move the core to Google Cloud, described in a separate `gcp/` configuration with
its own HCP Terraform workspace (`successfulsuccess-gcp`), so that one plan cannot
break both clouds.

| AWS today | Google Cloud | Decision |
|---|---|---|
| S3 + CloudFront (Free plan) + WAF, static frontend | Firebase Hosting | **Replace.** The same static export; `/api/**` is rewritten to Cloud Run, so the site and the API share one origin and need no CORS, as CloudFront did. |
| Lambda + function URL, FastAPI | Cloud Run | **Replace.** It runs `backend/Dockerfile`, the image compose already used, on the port in `PORT`. Mangum, the Lambda adapter, is now an extra that only `Dockerfile.lambda` installs. |
| ECR | Artifact Registry | **Replace.** |
| RDS PostgreSQL `db.t3.micro` | Cloud SQL for PostgreSQL 17, `db-f1-micro`, 10 GB SSD | **Replace**, and stop it when nobody uses it (`db_running = false`). |
| DynamoDB | Firestore | **Drop.** The app does not use DynamoDB. |
| Cognito user pool + Google | Identity Platform | **Keep Cognito for now.** The API on Cloud Run checks Cognito tokens exactly as on Lambda. Moving would mean moving every account. |
| EventBridge Scheduler | Cloud Scheduler | **Keep on AWS** with the weekly report. |
| SQS | Pub/Sub or Cloud Tasks | **Keep on AWS** with the weekly report. |
| S3 event → Lambda | Cloud Storage + Eventarc → Cloud Run | **Keep on AWS** with the weekly report. |
| SES | no Google service | **Keep SES.** |
| Bedrock (Claude) | Vertex AI | **Keep on AWS** with the agenda parser. |
| CloudFormation parameters, HCP sensitive variables | Secret Manager | **Replace.** Terraform generates the database password and stores the whole connection URL; only the API's service account may read it. |
| CloudWatch Logs | Cloud Logging | **Replace.** Cloud Run sends standard output there with no setup. |
| IAM roles | Service accounts + IAM roles | **Replace.** One service account per program: `hcp-terraform` applies `gcp/`, `successfulsuccess-api` runs the API with only `cloudsql.client` and access to its one secret. Neither has Owner or Editor. |
| Terraform `aws` provider, dynamic credentials | Terraform `google` provider, Workload Identity Federation | **Replace.** HCP Terraform exchanges its run token for a short-lived token of `hcp-terraform`. The pool admits one organization and one workspace, by ID. No key exists. |

**The data** is loaded by running the migrations against the empty database:
`entrypoint.sh` runs `alembic upgrade head` when the container starts. A
`pg_dump` from AWS was not possible without changing AWS: the RDS instance is
private and was stopped.

### The database

| Option | Latency | Bill (nobody using it) | Code |
|---|---|---|---|
| Cloud SQL around the clock | Lowest: same region as Cloud Run, Unix socket | about $9.40 a month | No change |
| Cloud SQL stopped when unused | The same once it runs; the first request fails until someone starts it | about $1.70 plus $0.0105 per running hour | No change |
| Firestore | Low | $0 within the daily free quota | Rewrite: the models, the repositories and the migrations, since meetings, participants, agendas and users are relations |
| Keep RDS on AWS, call it from Cloud Run | Every query crosses from us-central1 to us-east-1, tens of milliseconds each, several per request | RDS as today, plus egress both ways | Small, but RDS is private in its VPC: it would need a public address or a VPN |

**Decision: Cloud SQL, stopped when nobody uses it.** The app is relational, and
saving about $8 a month does not justify rewriting its data layer.

### E-mail

The weekly report and SES stay on AWS, so nothing changes. If the report moves, it
would go through SendGrid or Mailgun, with its API key in Secret Manager, readable
only by the report's service account.

### What does not move

- **The weekly report.** It works, and moving it means rebuilding five services
  (schedule, queue, builder, bucket trigger, mailer) with different triggers.
- **The agenda parser.** Its prompt was tuned for Claude on Bedrock in Lab 6, and the
  Google trial credit does not pay for Claude on Vertex AI.
- **Sign-in.** Moving the user pool means every user signs up again or resets a
  password.

## Consequences

- The app runs on two clouds: the browser talks to Google, and the API checks
  tokens issued by AWS. That is a migration state, not a goal; the stretch goals
  close it piece by piece.
- Cloud SQL does not pause like a serverless database. It must be stopped by hand
  (`terraform apply -var db_running=false`), and its storage bills even then.
- The Terraform state of `gcp/` holds the database password. It lives only in HCP
  Terraform, which encrypts it.
- The configuration passes `terraform init` and `terraform validate`. It was not
  applied: no Google Cloud project was used for this lab, and the Cloud Run image
  was run locally, as Cloud Run would run it, next to a local PostgreSQL.
