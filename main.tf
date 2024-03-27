resource "random_id" "project_suffix" {
  byte_length = 4
}

resource "google_project" "project" {
  name            = "sandbox-docs"
  project_id      = "sandbox-docs-${random_id.project_suffix.dec}"
  org_id          = var.organization_id
  billing_account = var.billing_account
}

resource "google_project_service" "services" {
  for_each = toset([
    "compute.googleapis.com",
    "iam.googleapis.com",
    "storage.googleapis.com",
  ])
  project = google_project.project.project_id
  service = each.key
}

resource "google_project_organization_policy" "public_access" {
  project    = google_project.project.project_id
  constraint = "storage.publicAccessPrevention"

  boolean_policy {
    enforced = false
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "docs" {
  name          = "${google_project.project.name}-bucket-${random_id.bucket_suffix.dec}"
  location      = "US"
  project       = google_project.project.project_id
  storage_class = "STANDARD"
  force_destroy = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  depends_on = [
    google_project_service.services["storage.googleapis.com"]
  ]
}

resource "google_storage_bucket_iam_member" "public_access" {
  bucket = google_storage_bucket.docs.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"

  depends_on = [
    google_project_organization_policy.public_access
  ]
}

resource "google_compute_global_address" "default" {
  name    = "docs-sandboxaq-com-public-ip"
  project = google_project.project.project_id

  depends_on = [
    google_project_service.services["compute.googleapis.com"]
  ]
}

resource "google_compute_managed_ssl_certificate" "default" {
  name    = "docs-sandboxaq-com-certificate"
  project = google_project.project.project_id

  managed {
    domains = ["docs.sandboxaq.com."]
  }

  depends_on = [
    google_project_service.services["compute.googleapis.com"]
  ]
}

resource "google_compute_backend_bucket" "default" {
  name        = "sandbox-docs-bucket-backend"
  project     = google_project.project.project_id
  description = "Backend for ${google_storage_bucket.docs.name} bucket"
  bucket_name = google_storage_bucket.docs.name
}

resource "google_compute_url_map" "https_url_map" {
  name        = "docs-sandboxaq-com-https-url-map"
  project     = google_project.project.project_id
  description = "URL map for docs.sandboxaq.com domain"

  default_service = google_compute_backend_bucket.default.id
}

resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "docs-sandboxaq-com-https-proxy"
  project          = google_project.project.project_id
  url_map          = google_compute_url_map.https_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

resource "google_compute_global_forwarding_rule" "https_load_balancer" {
  name                  = "docs-sandboxaq-com-https-lb"
  project               = google_project.project.project_id
  ip_protocol           = "TCP"
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"
  target                = google_compute_target_https_proxy.https_proxy.id
  ip_address            = google_compute_global_address.default.id
}

resource "google_compute_url_map" "http_url_map" {
  name    = "docs-sandboxaq-com-http-url-map"
  project = google_project.project.project_id

  default_url_redirect {
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
    https_redirect         = true
  }

  depends_on = [
    google_project_service.services["compute.googleapis.com"]
  ]
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "docs-sandboxaq-com-http-proxy"
  project = google_project.project.project_id
  url_map = google_compute_url_map.http_url_map.self_link
}

resource "google_compute_global_forwarding_rule" "http_load_balancer" {
  name        = "docs-sandboxaq-com-http-lb"
  project     = google_project.project.project_id
  ip_protocol = "TCP"
  port_range  = "80"
  target      = google_compute_target_http_proxy.http_proxy.id
  ip_address  = google_compute_global_address.default.address
}
