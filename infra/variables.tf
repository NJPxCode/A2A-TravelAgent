variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_project_name" {
  description = "GCP project display name"
  type        = string
}

variable "gcp_billing_account_id" {
  description = "GCP billing account ID"
  type        = string
}

variable "gcp_org_id" {
  description = "GCP organization ID (optional, leave empty for standalone projects)"
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region for Cloud Run and Artifact Registry"
  type        = string
  default     = "us-central1"
}

variable "github_repo" {
  description = "GitHub repository in 'owner/repo' format for Workload Identity Federation"
  type        = string
}

variable "llm_model" {
  description = "LLM model identifier (e.g. openai/gpt-4o-mini)"
  type        = string
  default     = "openai/gpt-4o-mini"
}

variable "llm_api_key" {
  description = "API key for the LLM provider"
  type        = string
  sensitive   = true
}

variable "llm_api_key_env_name" {
  description = "Environment variable name for the LLM API key in Cloud Run"
  type        = string
  default     = "OPENAI_API_KEY"
}
