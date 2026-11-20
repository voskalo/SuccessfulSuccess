# The API reads its whole connection string, password included, from Secret
# Manager. The host is the Unix socket that the Cloud SQL volume mounts in Cloud Run.
resource "google_secret_manager_secret" "database_url" {
  secret_id = "${var.project_name}-database-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret = google_secret_manager_secret.database_url.id
  secret_data = format(
    "postgresql+asyncpg://%s:%s@/%s?host=/cloudsql/%s",
    google_sql_user.app.name,
    random_password.db.result,
    google_sql_database.meetings.name,
    google_sql_database_instance.db.connection_name,
  )
}

# Only the API's own service account may read it.
resource "google_secret_manager_secret_iam_member" "api_reads_database_url" {
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.api_service_account}"
}
