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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Its own workspace, apart from infra/ (successfulsuccess-dev): one plan cannot
  # break both clouds. HCP Terraform reaches Google through Workload Identity
  # Federation, set up by gcp/bootstrap, with no service account key anywhere.
  cloud {
    organization = "ooad-voskalo"

    workspaces {
      name = "successfulsuccess-gcp"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    project_name = var.project_name
  }
}

# Firebase Hosting sites exist only in the beta provider.
provider "google-beta" {
  project = var.project_id
  region  = var.region

  default_labels = {
    project_name = var.project_name
  }
}
