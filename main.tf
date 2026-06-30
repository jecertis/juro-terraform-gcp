# Juro Tier 3 agent — GCP infrastructure module
#
# Provisions the full Juro agent stack inside the customer's GCP project.
# Agent runs on Cloud Run with Workload Identity; scans are scheduled via
# Cloud Scheduler. See contracts/tier-3-install.md §Phase 1 for the expected
# resource set.
#
# Customer applies this in their own Terraform state. The PR and plan output
# are the customer's audit trail. Do NOT apply from Juro's environment.

locals {
  name_prefix = "juro-agent-${var.engagement_slug}"
  common_labels = {
    engagement_slug = var.engagement_slug
    purpose         = "juro-compliance-scan"
    managed_by      = "juro-terraform-gcp"
  }
}

# -----------------------------------------------------------------------------
# APIs — enable required GCP APIs in the customer project
# -----------------------------------------------------------------------------

resource "google_project_service" "required" {
  for_each = toset([
    "run.googleapis.com",
    "cloudscheduler.googleapis.com",
    "iam.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# Service account — agent identity
# No service account key. Agent authenticates via Cloud Run Workload Identity.
# -----------------------------------------------------------------------------

resource "google_service_account" "agent" {
  project      = var.project_id
  account_id   = "juro-agent"
  display_name = "Juro Tier 3 Agent (read-only)"
  description  = "Read-only access for the Juro compliance agent. Engagement: ${var.engagement_slug}. Expires ${var.expires_at}."

  depends_on = [google_project_service.required]
}

# -----------------------------------------------------------------------------
# Custom IAM role — read-only allowlist
# Permission list sourced from contracts/iam-policy-gcp.md.
# Sorted alphabetically — juro preflight hashes this list and refuses
# to run if the deployed role does not match the published hash.
# -----------------------------------------------------------------------------

resource "google_project_iam_custom_role" "agent" {
  project     = var.project_id
  role_id     = "juroCompliantTier3Agent"
  title       = "Juro Tier 3 Agent (read-only)"
  description = "Generated from contracts/iam-policy-gcp.md. Engagement: ${var.engagement_slug}. Expires ${var.expires_at}."
  stage       = "GA"

  permissions = [
    "alloydb.clusters.get",
    "alloydb.clusters.list",
    "alloydb.instances.get",
    "alloydb.instances.list",
    "apigateway.apis.get",
    "apigateway.apis.list",
    "apigateway.gateways.get",
    "apigateway.gateways.list",
    "bigquery.datasets.get",
    "bigquery.datasets.getIamPolicy",
    "bigquery.tables.get",
    "bigquery.tables.getIamPolicy",
    "bigquery.tables.list",
    "bigtable.appProfiles.get",
    "bigtable.appProfiles.list",
    "bigtable.clusters.get",
    "bigtable.clusters.list",
    "bigtable.instances.get",
    "bigtable.instances.list",
    "bigtable.tables.get",
    "bigtable.tables.list",
    "cloudasset.assets.searchAllIamPolicies",
    "cloudasset.assets.searchAllResources",
    "cloudfunctions.functions.get",
    "cloudfunctions.functions.getIamPolicy",
    "cloudfunctions.functions.list",
    "cloudkms.cryptoKeyVersions.list",
    "cloudkms.cryptoKeys.get",
    "cloudkms.cryptoKeys.getIamPolicy",
    "cloudkms.cryptoKeys.list",
    "cloudkms.keyRings.get",
    "cloudkms.keyRings.list",
    "cloudkms.locations.get",
    "cloudkms.locations.list",
    "cloudsql.backupRuns.list",
    "cloudsql.databases.get",
    "cloudsql.databases.list",
    "cloudsql.instances.get",
    "cloudsql.instances.list",
    "cloudsql.users.list",
    "compute.disks.get",
    "compute.disks.list",
    "compute.firewalls.get",
    "compute.firewalls.list",
    "compute.instances.get",
    "compute.instances.getIamPolicy",
    "compute.instances.list",
    "compute.networks.get",
    "compute.networks.list",
    "compute.routers.get",
    "compute.routers.list",
    "compute.routes.get",
    "compute.routes.list",
    "compute.snapshots.get",
    "compute.snapshots.list",
    "compute.sslCertificates.get",
    "compute.sslCertificates.list",
    "compute.subnetworks.get",
    "compute.subnetworks.list",
    "compute.targetHttpsProxies.get",
    "compute.targetHttpsProxies.list",
    "compute.urlMaps.get",
    "compute.urlMaps.list",
    "container.clusters.get",
    "container.clusters.list",
    "container.nodePools.get",
    "container.nodePools.list",
    "container.operations.get",
    "container.operations.list",
    "datastore.databases.get",
    "datastore.databases.list",
    "datastore.indexes.get",
    "datastore.indexes.list",
    "datastore.namespaces.list",
    "dns.managedZones.get",
    "dns.managedZones.list",
    "iam.roles.get",
    "iam.roles.list",
    "iam.serviceAccountKeys.list",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.list",
    "logging.buckets.get",
    "logging.buckets.list",
    "logging.exclusions.get",
    "logging.exclusions.list",
    "logging.locations.get",
    "logging.locations.list",
    "logging.logMetrics.get",
    "logging.logMetrics.list",
    "logging.sinks.get",
    "logging.sinks.list",
    "pubsub.schemas.get",
    "pubsub.schemas.list",
    "pubsub.subscriptions.get",
    "pubsub.subscriptions.getIamPolicy",
    "pubsub.subscriptions.list",
    "pubsub.topics.get",
    "pubsub.topics.getIamPolicy",
    "pubsub.topics.list",
    "resourcemanager.projects.get",
    "resourcemanager.projects.getIamPolicy",
    "resourcemanager.tagBindings.list",
    "resourcemanager.tagKeys.get",
    "resourcemanager.tagKeys.list",
    "resourcemanager.tagValues.get",
    "resourcemanager.tagValues.list",
    "run.jobs.get",
    "run.jobs.list",
    "run.revisions.get",
    "run.revisions.list",
    "run.services.get",
    "run.services.getIamPolicy",
    "run.services.list",
    "securitycenter.findings.group",
    "securitycenter.sources.list",
    "secretmanager.secrets.get",
    "secretmanager.secrets.getIamPolicy",
    "secretmanager.secrets.list",
    "secretmanager.versions.list",
    "spanner.backups.get",
    "spanner.backups.list",
    "spanner.databases.get",
    "spanner.databases.getDdl",
    "spanner.databases.list",
    "spanner.instances.get",
    "spanner.instances.list",
    "storage.buckets.get",
    "storage.buckets.getIamPolicy",
    "storage.buckets.list",
  ]

  depends_on = [google_project_service.required]
}

# Project-scope binding — non-authoritative (adds one binding, does not disturb others)
resource "google_project_iam_member" "agent" {
  project = var.project_id
  role    = google_project_iam_custom_role.agent.id
  member  = "serviceAccount:${google_service_account.agent.email}"
}

# -----------------------------------------------------------------------------
# Artifact store — GCS bucket write access
# Agent writes signed findings to the customer-owned bucket.
# Only objectCreator (PutObject equivalent) — no read, no delete.
# -----------------------------------------------------------------------------

resource "google_storage_bucket_iam_member" "agent_artifact_write" {
  bucket = var.artifact_store_bucket
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.agent.email}"
}

# -----------------------------------------------------------------------------
# Secret Manager — config values the agent reads at startup
# -----------------------------------------------------------------------------

resource "google_secret_manager_secret" "rule_pack_registry" {
  project   = var.project_id
  secret_id = "juro-${var.engagement_slug}-rule-pack-registry"

  replication {
    auto {}
  }

  labels     = local.common_labels
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "rule_pack_registry" {
  secret      = google_secret_manager_secret.rule_pack_registry.id
  secret_data = var.rule_pack_registry
}

resource "google_secret_manager_secret_iam_member" "agent_rule_pack" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.rule_pack_registry.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.agent.email}"
}

resource "google_secret_manager_secret" "telemetry_enabled" {
  project   = var.project_id
  secret_id = "juro-${var.engagement_slug}-telemetry-enabled"

  replication {
    auto {}
  }

  labels     = local.common_labels
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "telemetry_enabled" {
  secret      = google_secret_manager_secret.telemetry_enabled.id
  secret_data = tostring(var.telemetry_enabled)
}

resource "google_secret_manager_secret_iam_member" "agent_telemetry" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.telemetry_enabled.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.agent.email}"
}

# -----------------------------------------------------------------------------
# Cloud Run service — the agent container
# Runs on-demand (max-instances=1) and is invoked by Cloud Scheduler.
# Not publicly accessible — unauthenticated invocations denied.
# -----------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "agent" {
  project  = var.project_id
  name     = local.name_prefix
  location = var.gcp_region

  template {
    service_account = google_service_account.agent.email

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    containers {
      image = "ghcr.io/jecertis/cloud-scanner:${var.agent_image_tag}"

      env {
        name  = "JURO_ENGAGEMENT_SLUG"
        value = var.engagement_slug
      }

      env {
        name  = "JURO_ARTIFACT_STORE"
        value = "gs://${var.artifact_store_bucket}/juro/${var.engagement_slug}"
      }

      env {
        name  = "JURO_OIDC_ISSUER"
        value = var.oidc_issuer
      }

      env {
        name  = "JURO_CLOUD"
        value = "gcp"
      }

      env {
        name  = "JURO_REGION"
        value = var.gcp_region
      }

      env {
        name  = "JURO_PROJECT_ID"
        value = var.project_id
      }

      env {
        name = "JURO_RULE_PACK_REGISTRY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.rule_pack_registry.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "JURO_TELEMETRY_ENABLED"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.telemetry_enabled.secret_id
            version = "latest"
          }
        }
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }
    }
  }

  labels     = local.common_labels
  depends_on = [google_project_service.required]
}

# Block unauthenticated invocations
resource "google_cloud_run_v2_service_iam_binding" "no_public_access" {
  project  = var.project_id
  location = var.gcp_region
  name     = google_cloud_run_v2_service.agent.name
  role     = "roles/run.invoker"
  members  = []
}

# Cloud Scheduler service account — allowed to invoke the Cloud Run service
resource "google_service_account" "scheduler" {
  project      = var.project_id
  account_id   = "juro-scheduler"
  display_name = "Juro Cloud Scheduler invoker"
  description  = "Allows Cloud Scheduler to trigger the Juro agent Cloud Run service. Engagement: ${var.engagement_slug}."
}

resource "google_cloud_run_v2_service_iam_member" "scheduler_invoke" {
  project  = var.project_id
  location = var.gcp_region
  name     = google_cloud_run_v2_service.agent.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}

# -----------------------------------------------------------------------------
# Cloud Scheduler — scheduled scan job
# -----------------------------------------------------------------------------

resource "google_cloud_scheduler_job" "scan_schedule" {
  project   = var.project_id
  region    = var.gcp_region
  name      = "${local.name_prefix}-schedule"
  schedule  = var.scan_schedule
  time_zone = var.scan_schedule_timezone

  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.agent.uri}/scan"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
      audience              = google_cloud_run_v2_service.agent.uri
    }
  }

  depends_on = [google_project_service.required]
}
