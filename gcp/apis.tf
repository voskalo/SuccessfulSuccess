# A fresh project has every API switched off. The ones this configuration
# manages are enabled here; the ones the bootstrap needs are enabled there.
locals {
  services = [
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "firebasehosting.googleapis.com",
  ]
}

resource "google_project_service" "this" {
  for_each = toset(local.services)

  service = each.value
  # Destroying this configuration must not switch the API off for anything else.
  disable_on_destroy = false
}
