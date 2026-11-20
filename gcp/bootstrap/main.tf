# Part 0, applied once from a laptop with your own gcloud login
# (gcloud auth application-default login). Its state stays local: it creates the
# identity that HCP Terraform later uses for gcp/, so it cannot run there itself.

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
  }
}

variable "project_id" {
  description = "The Google Cloud project, created in the console with billing linked."
  type        = string
}

variable "billing_account" {
  description = "The billing account the budget watches (Billing → Account management)."
  type        = string
}

variable "project_name" {
  type    = string
  default = "successfulsuccess"
}

# Immutable IDs, not names: a name can be taken by someone else after a rename.
variable "hcp_organization_id" {
  description = "The HCP Terraform organization (org-...), from its API or settings."
  type        = string
}

variable "hcp_workspace_id" {
  description = "The successfulsuccess-gcp workspace (ws-...), from its settings."
  type        = string
}

provider "google" {
  project               = var.project_id
  user_project_override = true
  billing_project       = var.project_id
}

provider "google-beta" {
  project = var.project_id
}

resource "google_project_service" "this" {
  for_each = toset([
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "firebase.googleapis.com",
    "billingbudgets.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# Alerts only: e-mails at 50%, 90% and 100% of $5 a month. It does not stop spending.
resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account
  display_name    = "${var.project_name} monthly"

  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = "5"
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }

  depends_on = [google_project_service.this]
}

data "google_project" "this" {}

# --- Service accounts: one per program, none with Owner or Editor ---------------

resource "google_service_account" "terraform" {
  account_id   = "hcp-terraform"
  display_name = "HCP Terraform, applies gcp/"
  depends_on   = [google_project_service.this]
}

resource "google_project_iam_member" "terraform" {
  for_each = toset([
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/artifactregistry.admin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/iam.serviceAccountUser",
    "roles/firebasehosting.admin",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

resource "google_service_account" "api" {
  account_id   = "${var.project_name}-api"
  display_name = "The API on Cloud Run"
  depends_on   = [google_project_service.this]
}

resource "google_project_iam_member" "api_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# --- Workload Identity Federation: HCP Terraform signs in with no key -------------

resource "google_iam_workload_identity_pool" "hcp" {
  workload_identity_pool_id = "hcp-terraform"
  display_name              = "HCP Terraform"
  depends_on                = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "hcp" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.hcp.workload_identity_pool_id
  workload_identity_pool_provider_id = "hcp-terraform"
  display_name                       = "app.terraform.io"

  attribute_mapping = {
    "google.subject"                      = "assertion.sub"
    "attribute.terraform_organization_id" = "assertion.terraform_organization_id"
    "attribute.terraform_workspace_id"    = "assertion.terraform_workspace_id"
  }

  # Only runs of this one workspace, in this one organization, get in.
  attribute_condition = "assertion.terraform_organization_id == \"${var.hcp_organization_id}\" && assertion.terraform_workspace_id == \"${var.hcp_workspace_id}\""

  oidc {
    issuer_uri = "https://app.terraform.io"
  }
}

resource "google_service_account_iam_member" "hcp_impersonates_terraform" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.hcp.name}/attribute.terraform_workspace_id/${var.hcp_workspace_id}"
}

# Firebase must be added to the project once before gcp/ can create a Hosting site.
resource "google_firebase_project" "this" {
  provider   = google-beta
  project    = var.project_id
  depends_on = [google_project_service.this]
}

# --- What to set on the successfulsuccess-gcp workspace (environment variables) ---

output "TFC_GCP_PROVIDER_AUTH" {
  value = "true"
}

output "TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL" {
  value = google_service_account.terraform.email
}

output "TFC_GCP_WORKLOAD_PROVIDER_NAME" {
  value = google_iam_workload_identity_pool_provider.hcp.name
}
