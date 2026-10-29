# ADR 0007: Manage sign-in, reports and the agenda parser with Terraform

- Status: Accepted
- Date: 2026-10-29

## Context

Labs 4 to 6 added three CloudFormation templates: `infra/auth.yml` (Cognito),
`infra/reports.yml` (the weekly report) and `infra/ai.yml` (the agenda parser).
They worked, but each was deployed from a laptop with `make aws-deploy-*`, with
parameters assembled from other stacks' outputs and from `.env`. Nobody could see
a change before it happened, and nothing recorded who applied what.

The project also reaches outside AWS: the Google OAuth client for sign-in, and the
GitHub repository and its pipeline. It will need a second environment.

The resources hold data that must survive the move: the user pool has every
account that signed up, and the reports bucket has every report.

## Decision

- **Terraform**, in `infra/*.tf`, replaces the three templates. One root module, one
  HCP Terraform workspace (`ooad-voskalo/successfulsuccess-dev`) in remote execution
  mode.
- **The existing resources were adopted, not re-created.** The three stacks got
  `DeletionPolicy: Retain` on all 26 resources and were deleted, and Terraform took
  the resources over with `import` blocks (33 imports, since Terraform splits some
  CloudFormation resources in two). The plan showed nothing destroyed or replaced
  before it was applied. Four managed-policy attachments were created fresh: they
  were already attached, so creating them changed nothing.
- **Who changes the infrastructure:** anyone with a pull request. HCP Terraform
  posts the plan as a check, and applies after the merge to `main`. It reaches AWS
  with dynamic credentials: a short-lived token exchanged for the role
  `hcp-terraform-ooad-voskalo` through an IAM OIDC provider. The Makefile only plans
  (`make infra-plan`) and reads outputs. It never applies.
- **Secrets** are sensitive workspace variables (`db_password`,
  `google_client_secret`), never files. Non-secret values are in
  `infra/terraform.tfvars`.
- **The user pool and the reports bucket have `prevent_destroy`.**
- The backend, frontend and ECR stacks stay CloudFormation for now. Terraform reads
  what it needs from them with data sources (the database, its security group).

## Alternatives considered

- **Keep CloudFormation.** AWS keeps the state and rolls back failed changes. It
  lost because it stops at the AWS account: the Google client and GitHub cannot be
  in the same plan, and a second environment means copying stacks by hand.
- **AWS CDK.** Real code (TypeScript or Python) on top of CloudFormation. It lost
  because it keeps CloudFormation's AWS-only limit, and it adds a build step and a
  language runtime to the infrastructure.
- **OpenTofu.** The open-source fork accepts the same files and commands. It lost
  narrowly: the course uses HCP Terraform for state and runs, and the BSL licence
  of Terraform does not affect a class project. Switching later means changing the
  binary, not the code.

## Consequences

- **Every change is reviewed as a plan** before it reaches AWS, and every plan
  compares the code with the real resources, so drift shows up on the next run.
- **The state is ours to protect.** It lives in HCP Terraform, locked during every
  run and versioned. It contains every attribute in plain form, including the
  database password (in the report builder's `DATABASE_URL`) and the Google client
  secret. `sensitive = true` hides them in plan output, not in the state. Access to
  the HCP organization is therefore access to those secrets.
- **The bootstrap role has AdministratorAccess** and trusts any workspace of the
  organization. That is acceptable for the class project and the first thing to
  narrow: one workspace in the trust condition, and only the services this
  workspace manages (Cognito, Lambda, S3, SQS, Scheduler, IAM for its own roles,
  Logs, Budgets, EC2 VPC endpoints).
- **When HCP Terraform is down,** nothing that already runs is affected: the site,
  sign-in, the API, the parser and the weekly report keep working. Only changes to
  this infrastructure wait. In an emergency, the workspace can be switched to local
  execution and planned and applied from a laptop with the same state, and switched
  back afterwards.
- **Terraform has no automatic rollback.** A failed apply stops halfway, and the fix
  is a new commit and another apply.
