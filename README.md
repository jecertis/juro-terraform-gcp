# juro-terraform-gcp

Terraform module for deploying the Juro Tier 3 compliance agent inside a customer's GCP project.

The customer applies this module in their own Terraform state. Juro never has access to the customer's
GCP environment — all provisioning runs from the customer side.

## What this module provisions

- **Cloud Run service** — runs the Juro agent container (pinned image tag) on-demand, max one instance,
  no public access; invoked by Cloud Scheduler.
- **Custom IAM role + service account** — read-only, least-privilege role (`juroCompliantTier3Agent`)
  bound to a dedicated service account. No service account key is created; the agent authenticates via
  Cloud Run Workload Identity.
- **Cloud Scheduler job** — triggers a POST to `/scan` on the Cloud Run service URI on a configurable
  cron schedule (default: daily at 03:00 UTC).
- **Secret Manager secrets** — stores rule-pack registry URL and telemetry flag; only the agent service
  account can access them.
- **GCS artifact write access** — grants `roles/storage.objectCreator` on the customer-owned artifact
  bucket. The agent writes signed findings there; it cannot read or delete objects.

## Prerequisites

- A GCP project where you have `roles/owner` or sufficient permissions to create service accounts,
  custom roles, Cloud Run services, and Cloud Scheduler jobs.
- `terraform` >= 1.5.0 with the `hashicorp/google` provider ~> 5.0.
- `gcloud` CLI authenticated: `gcloud auth application-default login`.
- The following APIs enabled in the target project (or let Terraform enable them via `google_project_service`):
  - `run.googleapis.com`
  - `cloudscheduler.googleapis.com`
  - `iam.googleapis.com`
  - `storage.googleapis.com`
  - `secretmanager.googleapis.com`
  - `sqladmin.googleapis.com` *(for Cloud SQL collector)*
  - `bigquery.googleapis.com` *(for BigQuery collector)*
  - `cloudresourcemanager.googleapis.com`
  - `logging.googleapis.com`

## Variables

| Name | Description | Required | Example |
|------|-------------|----------|---------|
| `project_id` | Customer GCP project ID where the agent runs and reads from | yes | `acme-prod-123456` |
| `gcp_region` | GCP region for Cloud Run service and Cloud Scheduler job | yes | `asia-south1` |
| `agent_image_tag` | Pinned tag of the `ghcr.io/jecertis/cloud-scanner` image. Set from the SOW. | yes | `v1.4.2` |
| `engagement_slug` | Juro engagement slug (kebab-case). Used in resource names and labels. | yes | `acme-gdpr-2026` |
| `artifact_store_bucket` | Customer-owned GCS bucket where signed scan artifacts are written | yes | `acme-juro-artifacts` |
| `oidc_issuer` | OIDC provider URL for Workload Identity / Fulcio leaf certificate issuance | yes | `https://accounts.google.com` |
| `expires_at` | Engagement expiration date (RFC 3339). Run `terraform destroy` when engagement ends. | yes | `2027-06-30T00:00:00Z` |
| `rule_pack_registry` | OCI registry URL for Juro rule packs. Override only when mirroring internally. | no | `ghcr.io/jecertis/juro-rules` |
| `telemetry_enabled` | When false, agent does not publish records to the Juro transparency log. | no | `true` |
| `scan_schedule` | Cloud Scheduler cron expression for the scheduled scan. | no | `0 3 * * *` |
| `scan_schedule_timezone` | Timezone for the Cloud Scheduler schedule. | no | `Etc/UTC` |

## Usage

```bash
gcloud auth application-default login

terraform init

terraform plan \
  -var="project_id=YOUR_PROJECT" \
  -var="gcp_region=asia-south1" \
  -var="agent_image_tag=IMAGE_TAG" \
  -var="engagement_slug=YOUR_SLUG" \
  -var="artifact_store_bucket=YOUR_BUCKET" \
  -var="oidc_issuer=https://accounts.google.com" \
  -var="expires_at=2027-06-30T00:00:00Z"

terraform apply
```

Copy `terraform.tfvars.example` to `terraform.tfvars` and populate it to avoid passing vars on every
command. Keep `terraform.tfvars` out of version control — it contains engagement-specific values.

## Workload Identity setup

Juro's agent service account is created inside the customer's GCP project and runs as the Cloud Run
service identity. It holds a read-only custom role (`juroCompliantTier3Agent`) scoped to the project.
The agent authenticates exclusively via Cloud Run Workload Identity tokens — no service account key is
ever issued or stored. Tokens are short-lived and scoped to the duration of a single scan invocation.
Juro's infrastructure has no standing access to the customer project at any point.

## What the scanner reads

The agent's custom role grants read-only access to the following APIs. No write or delete permissions
are granted.

**IAM**
- `iam.roles.get/list`, `iam.serviceAccounts.get/list/getIamPolicy`, `iam.serviceAccountKeys.list`
- `resourcemanager.projects.get/getIamPolicy`

**Cloud Storage**
- `storage.buckets.get/list/getIamPolicy`

**Cloud SQL**
- `cloudsql.instances.get/list`, `cloudsql.databases.get/list`, `cloudsql.backupRuns.list`, `cloudsql.users.list`

**BigQuery**
- `bigquery.datasets.get/list/getIamPolicy`, `bigquery.tables.get/list/getIamPolicy`, `bigquery.routines.list`

**Logging**
- `logging.sinks.get/list`, `logging.buckets.get/list`, `logging.logMetrics.get/list`, `logging.exclusions.get/list`

**Compute / Networking**
- `compute.instances.get/list/getIamPolicy`, `compute.firewalls.get/list`, `compute.networks.get/list`,
  `compute.subnetworks.get/list`, `compute.disks.get/list`, `compute.snapshots.get/list`,
  `compute.routers.get/list`, `compute.routes.get/list`, `compute.sslCertificates.get/list`,
  `compute.targetHttpsProxies.get/list`, `compute.urlMaps.get/list`

**GKE**
- `container.clusters.get/list`, `container.nodePools.get/list`, `container.operations.get/list`

**Cloud Run**
- `run.services.get/list/getIamPolicy`, `run.revisions.get/list`, `run.jobs.get/list`

**Pub/Sub, Cloud Functions, Spanner, AlloyDB, Bigtable, Datastore, API Gateway, Cloud KMS, Secret Manager**
- List and get permissions only (see `main.tf` lines 65–198 for the full alphabetically sorted set).

**Cloud Asset Inventory**
- `cloudasset.assets.searchAllIamPolicies`, `cloudasset.assets.searchAllResources`

## Outputs

After `terraform apply`, `terraform output` returns:

| Output | Description |
|--------|-------------|
| `agent_service_url` | Cloud Run service URL. Use to trigger `juro preflight` or a manual scan. |
| `agent_service_account_email` | Agent service account email. |
| `agent_custom_role_id` | Fully qualified custom role ID. Pass to `juro preflight` for permission-hash verification. |
| `scheduler_job_name` | Cloud Scheduler job name. Verify with `gcloud scheduler jobs describe <name>`. |
| `rule_pack_registry_secret` | Secret Manager secret ID storing the rule-pack registry URL. |
| `expires_at` | Engagement expiration date (from input variable). |
