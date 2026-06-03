terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

provider "google" {
  project = var.project_id
  region  = var.gcp_region
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "Customer GCP project ID where the agent runs and reads from."
  type        = string
}

variable "gcp_region" {
  description = "GCP region for Cloud Run service and Cloud Scheduler job."
  type        = string
}

variable "agent_image_tag" {
  description = "Pinned tag of the ghcr.io/jecertis/cloud-scanner image. Set from the SOW."
  type        = string
}

variable "rule_pack_registry" {
  description = "OCI registry URL for Juro rule packs. Override only when mirroring internally."
  type        = string
  default     = "ghcr.io/jecertis/juro-rules"
}

variable "artifact_store_bucket" {
  description = "Customer-owned GCS bucket where signed scan artifacts are written."
  type        = string
}

variable "oidc_issuer" {
  description = "OIDC provider URL for Workload Identity / Fulcio leaf certificate issuance."
  type        = string
}

variable "telemetry_enabled" {
  description = "When false, the agent does not publish records to the Juro transparency log."
  type        = bool
  default     = true
}

variable "scan_schedule" {
  description = "Cloud Scheduler cron expression for the scheduled scan. Default is daily at 03:00 UTC."
  type        = string
  default     = "0 3 * * *"
}

variable "scan_schedule_timezone" {
  description = "Timezone for the Cloud Scheduler schedule. Default UTC."
  type        = string
  default     = "Etc/UTC"
}

variable "engagement_slug" {
  description = "Juro engagement slug (kebab-case). Used in resource names and labels."
  type        = string
}

# expires_at — engagement expiry (externally enforced)
#
# GCP IAM does not natively expire service accounts or custom roles. Enforcement is
# the customer's responsibility: when the engagement ends, run:
#
#   terraform destroy -var-file="terraform.tfvars"
#
# This removes all resources created by this module (service accounts, custom IAM
# role, Cloud Run service, Cloud Scheduler job, Secret Manager secrets). The artifact
# store bucket is customer-owned and is NOT destroyed — findings are retained by the
# customer per their own retention policy.
#
# Recommended: set a calendar reminder for the expires_at date at engagement start.
variable "expires_at" {
  description = "Engagement expiration date (RFC 3339). Externally enforced — GCP IAM does not natively expire roles. Run `terraform destroy -var-file=terraform.tfvars` when the engagement ends."
  type        = string
}
