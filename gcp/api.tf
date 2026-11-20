# The backend image: the plain backend/Dockerfile, with no Lambda adapter.
resource "google_artifact_registry_repository" "backend" {
  repository_id = var.project_name
  location      = var.region
  format        = "DOCKER"
  description   = "Backend images for Cloud Run"

  depends_on = [google_project_service.this]
}

locals {
  # Created by gcp/bootstrap, with roles/cloudsql.client on the project.
  api_service_account = "${var.project_name}-api@${var.project_id}.iam.gserviceaccount.com"
  image               = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backend.repository_id}/backend:${var.image_tag}"
  site_url            = "https://${google_firebase_hosting_site.frontend.site_id}.web.app"
}

resource "google_cloud_run_v2_service" "api" {
  name                = "${var.project_name}-api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = local.api_service_account

    # Scales to zero when nobody uses it. Two instances cap the database connections.
    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.db.connection_name]
      }
    }

    containers {
      image = local.image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        # Request-based billing: CPU is charged only while a request is handled.
        cpu_idle = true
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "APP_TIMEZONE"
        value = var.app_timezone
      }
      env {
        # The site calls the API through the Firebase rewrite, on its own origin.
        name  = "CORS_ORIGINS"
        value = local.site_url
      }
      env {
        name  = "COGNITO_REGION"
        value = var.cognito_region
      }
      env {
        name  = "COGNITO_USER_POOL_ID"
        value = var.cognito_user_pool_id
      }
      env {
        name  = "COGNITO_CLIENT_ID"
        value = var.cognito_client_id
      }
      env {
        # entrypoint.sh runs alembic upgrade head before uvicorn starts.
        name  = "RUN_MIGRATIONS_ON_START"
        value = "true"
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_iam_member.api_reads_database_url,
  ]
}

# Public, because the API checks the Cognito access token on every request itself.
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
