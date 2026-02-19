terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# ============================================================
# GCP Project
# ============================================================

resource "google_project" "this" {
  name            = var.gcp_project_name
  project_id      = var.gcp_project_id
  org_id          = var.gcp_org_id != "" ? var.gcp_org_id : null
  billing_account = var.gcp_billing_account_id

  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================
# Enable Required APIs
# ============================================================

resource "google_project_service" "run" {
  project            = google_project.this.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifact_registry" {
  project            = google_project.this.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secret_manager" {
  project            = google_project.this.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  project            = google_project.this.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "resource_manager" {
  project            = google_project.this.project_id
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam_credentials" {
  project            = google_project.this.project_id
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

# Wait for API propagation before creating resources
resource "time_sleep" "api_propagation" {
  create_duration = "60s"
  depends_on = [
    google_project_service.run,
    google_project_service.artifact_registry,
    google_project_service.secret_manager,
    google_project_service.iam,
    google_project_service.resource_manager,
    google_project_service.iam_credentials,
  ]
}

# ============================================================
# Service Accounts
# ============================================================

# CI/CD service account (GitHub Actions: build + deploy)
resource "google_service_account" "github_actions" {
  account_id   = "github-actions"
  display_name = "GitHub Actions CI/CD"
  project      = google_project.this.project_id
  depends_on   = [time_sleep.api_propagation]
}

resource "google_project_iam_member" "github_actions_run_admin" {
  project = google_project.this.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "github_actions_ar_writer" {
  project = google_project.this.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "github_actions_sa_user" {
  project = google_project.this.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Cloud Run runtime service account
resource "google_service_account" "cloud_run" {
  account_id   = "travel-agent-run"
  display_name = "Travel Agent Cloud Run"
  project      = google_project.this.project_id
  depends_on   = [time_sleep.api_propagation]
}

# ============================================================
# Workload Identity Federation (GitHub Actions OIDC)
# ============================================================

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions Pool"
  project                   = google_project.this.project_id
  depends_on                = [time_sleep.api_propagation]
}

resource "google_iam_workload_identity_pool_provider" "github_oidc" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"
  project                            = google_project.this.project_id

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == '${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# ============================================================
# Artifact Registry
# ============================================================

resource "google_artifact_registry_repository" "travel_agent" {
  location      = var.gcp_region
  repository_id = "travel-agent"
  format        = "DOCKER"
  description   = "Travel Agent container images"
  project       = google_project.this.project_id
  depends_on    = [time_sleep.api_propagation]
}

# ============================================================
# Secret Manager (LLM API Key)
# ============================================================

resource "google_secret_manager_secret" "llm_api_key" {
  secret_id = "llm-api-key"
  project   = google_project.this.project_id

  replication {
    auto {}
  }

  depends_on = [time_sleep.api_propagation]
}

resource "google_secret_manager_secret_version" "llm_api_key" {
  secret      = google_secret_manager_secret.llm_api_key.id
  secret_data = var.llm_api_key
}

# Grant Cloud Run SA access to the secret
resource "google_secret_manager_secret_iam_member" "cloud_run_access" {
  secret_id = google_secret_manager_secret.llm_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run.email}"
}

# ============================================================
# Cloud Run v2 Service
# ============================================================

resource "google_cloud_run_v2_service" "travel_agent" {
  name     = "travel-agent"
  location = var.gcp_region
  project  = google_project.this.project_id

  depends_on = [time_sleep.api_propagation]

  template {
    service_account = google_service_account.cloud_run.email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    max_instance_request_concurrency = 1
    timeout                          = "300s"

    containers {
      # Placeholder image — replaced by CI/CD on first deploy
      image = "us-docker.pkg.dev/cloudrun/container/hello:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
      }

      env {
        name  = "LLM_MODEL"
        value = var.llm_model
      }

      env {
        name = var.llm_api_key_env_name
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.llm_api_key.secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/.well-known/agent-card.json"
        }
        initial_delay_seconds = 10
        period_seconds        = 5
        failure_threshold     = 12
        timeout_seconds       = 3
      }

      liveness_probe {
        http_get {
          path = "/.well-known/agent-card.json"
        }
        period_seconds = 30
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }
}

# Allow unauthenticated access (public A2A endpoint)
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.travel_agent.name
  location = var.gcp_region
  project  = google_project.this.project_id
  role     = "roles/run.invoker"
  member   = "allUsers"
}
