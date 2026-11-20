output "site_url" {
  description = "The frontend on Firebase Hosting."
  value       = local.site_url
}

output "api_url" {
  description = "The API on Cloud Run."
  value       = google_cloud_run_v2_service.api.uri
}

output "image_repository" {
  description = "Where to push the backend image."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backend.repository_id}"
}

output "database_connection_name" {
  description = "For gcloud sql connect and the Cloud SQL Auth Proxy."
  value       = google_sql_database_instance.db.connection_name
}
