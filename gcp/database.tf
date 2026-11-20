# Cloud SQL for PostgreSQL, the smallest shared-core tier. Unlike Aurora on AWS it
# never pauses: it bills every hour until db_running = false stops it.
resource "google_sql_database_instance" "db" {
  name             = "${var.project_name}-db"
  database_version = "POSTGRES_17"
  region           = var.region

  # terraform destroy must be able to remove it when the lab is over.
  deletion_protection = false

  settings {
    # Shared-core tiers exist only in the Enterprise edition.
    edition           = "ENTERPRISE"
    tier              = "db-f1-micro"
    disk_type         = "PD_SSD"
    disk_size         = 10
    disk_autoresize   = false
    activation_policy = var.db_running ? "ALWAYS" : "NEVER"

    # Cloud Run connects through the Cloud SQL connector, which authenticates with
    # IAM. The public address accepts nothing else: there are no authorised networks.
    ip_configuration {
      ipv4_enabled = true
    }

    backup_configuration {
      enabled = false
    }
  }

  depends_on = [google_project_service.this]
}

resource "google_sql_database" "meetings" {
  name     = "meetings"
  instance = google_sql_database_instance.db.name
}

# Generated here, stored in Secret Manager, never written to the repository.
# Letters and digits only, so it goes into the connection URL without escaping.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "google_sql_user" "app" {
  name     = "app"
  instance = google_sql_database_instance.db.name
  password = random_password.db.result
}
