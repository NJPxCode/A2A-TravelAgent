output "service_url" {
  description = "Cloud Run service URL"
  value       = google_cloud_run_v2_service.travel_agent.uri
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository path"
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.travel_agent.repository_id}"
}

output "wif_provider" {
  description = "Workload Identity Federation provider full name"
  value       = google_iam_workload_identity_pool_provider.github_oidc.name
}

output "service_account_email" {
  description = "GitHub Actions service account email"
  value       = google_service_account.github_actions.email
}
