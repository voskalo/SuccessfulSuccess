# The static frontend. Firebase Hosting includes the CDN and the certificate, and
# frontend/firebase.json rewrites /api/** to the Cloud Run service, so the site
# and the API share one origin. Its content is deployed with the firebase CLI.
resource "google_firebase_hosting_site" "frontend" {
  provider = google-beta

  project = var.project_id
  site_id = "${var.project_id}-app"

  depends_on = [google_project_service.this]
}
