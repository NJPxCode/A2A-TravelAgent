# Local backend for initial setup.
# WARNING: tfstate will contain the LLM API key in plaintext.
# Migrate to GCS or Terraform Cloud for production use.
terraform {
  backend "local" {}
}
