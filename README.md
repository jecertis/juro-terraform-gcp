# juro-terraform-gcp

Terraform module for deploying the Juro Tier 3 compliance agent inside a customer's GCP project.
The agent runs on Cloud Run under a least-privilege read-only service account, reads GCP resource
state (IAM, Storage, Cloud SQL, BigQuery, and more), and writes signed posture findings to a
customer-owned GCS bucket. Juro never has access to the customer's GCP environment — all
provisioning and scanning runs from the customer side under the customer's own credentials.

## What this module provisions

- **Cloud Run service** — runs the Juro agent container (pinned image tag) on-demand, max one
  instance, no public access; invoked by Cloud Scheduler or on demand.
- **Custom IAM role + service account** — read-only, least-privilege role (`juroCompliantTier3Agent`)
  bound to a dedicated service account. No service account key is created; the agent authenticates
  via Cloud Run Workload Identity.
- **Cloud Scheduler job** — triggers a `POST /scan` to the Cloud Run service URI on a configurable
  cron schedule (default: daily at 03:00 UTC).
- **Secret Manager secrets** — stores rule-pack registry URL and telemetry flag; only the agent
  service account can access them.
- **GCS artifact write access** — grants `roles/storage.objectCreator` on the customer-owned
  artifact bucket. The agent writes signed findings there; it cannot read or delete objects.

## Prerequisites

- A GCP project where you have `roles/owner` or equivalent permissions to create service accounts,
  custom IAM roles, Cloud Run services, and Cloud Scheduler jobs.
- `terraform` >= 1.5.0 with the `hashicorp/google` provider `~> 5.0`.
- `gcloud` CLI authenticated: `gcloud auth application-default login`.
- A customer-owned GCS bucket to receive signed scan artifacts.
- The following APIs enabled in the target project (Terraform enables them automatically via
  `google_project_service` if your identity has `serviceusage.services.enable`):
  - `run.googleapis.com`
  - `cloudscheduler.googleapis.com`
  - `iam.googleapis.com`
  - `storage.googleapis.com`
  - `secretmanager.googleapis.com`
  - `sqladmin.googleapis.com` *(Cloud SQL collector)*
  - `bigquery.googleapis.com` *(BigQuery collector)*
  - `cloudresourcemanager.googleapis.com`
  - `logging.googleapis.com`

## Quick start

```bash
# 1. Authenticate
gcloud auth application-default login

# 2. Clone and enter the module
git clone https://github.com/jecertis/juro-terraform-gcp.git
cd juro-terraform-gcp
git checkout v1.0.0   # version pinned in the SOW

# 3. Create your tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — see variables table below

# 4. Init, plan, apply
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

Keep `terraform.tfvars` out of version control — it contains engagement-specific values.

## Variables

| Name | Type | Description | Required | Default |
|------|------|-------------|----------|---------|
| `project_id` | `string` | Customer GCP project ID where the agent runs and reads from | yes | — |
| `gcp_region` | `string` | GCP region for Cloud Run service and Cloud Scheduler job | yes | — |
| `agent_image_tag` | `string` | Pinned tag of the `ghcr.io/jecertis/cloud-scanner` image. Set from the SOW. | yes | — |
| `engagement_slug` | `string` | Juro engagement slug (kebab-case). Used in resource names and labels. | yes | — |
| `artifact_store_bucket` | `string` | Customer-owned GCS bucket where signed scan artifacts are written | yes | — |
| `oidc_issuer` | `string` | OIDC provider URL for Workload Identity / Fulcio leaf certificate issuance | yes | — |
| `expires_at` | `string` | Engagement expiration date (RFC 3339). Run `terraform destroy` when engagement ends. | yes | — |
| `rule_pack_registry` | `string` | OCI registry URL for Juro rule packs. Override only when mirroring internally. | no | `ghcr.io/jecertis/juro-rules` |
| `telemetry_enabled` | `bool` | When false, agent does not publish records to the Juro transparency log. | no | `true` |
| `scan_schedule` | `string` | Cloud Scheduler cron expression for the scheduled scan. | no | `0 3 * * *` |
| `scan_schedule_timezone` | `string` | Timezone for the Cloud Scheduler schedule. | no | `Etc/UTC` |

## Outputs

After `terraform apply`, `terraform output` returns:

| Output | Description |
|--------|-------------|
| `agent_service_url` | Cloud Run service URL. Use to trigger `juro preflight` or a manual scan. |
| `agent_service_account_email` | Agent service account email. |
| `agent_custom_role_id` | Fully qualified custom role ID (`projects/<id>/roles/juroCompliantTier3Agent`). Pass to `juro preflight` for permission-hash verification. |
| `scheduler_job_name` | Cloud Scheduler job name. Verify state with `gcloud scheduler jobs describe <name>`. |
| `rule_pack_registry_secret` | Secret Manager secret ID storing the rule-pack registry URL. |
| `expires_at` | Engagement expiration date (from input variable). |

## Regulations and collectors

The agent ships four collectors in the initial release. Each collector maps to one or more regulation
articles in the active rule packs.

| Collector | GCP resource | Regulations | Example posture gaps surfaced |
|-----------|-------------|-------------|-------------------------------|
| **IAM** | Service accounts, custom roles, project IAM policy | GDPR Art. 25 (data protection by design), DPDP §8 (data fiduciary obligations), DORA Art. 9 (access management) | Service account keys in active use; primitive roles (`roles/owner`) bound to human accounts |
| **Cloud Storage** | GCS buckets — public access, IAM, logging | GDPR Art. 5(1)(f) (integrity and confidentiality), DPDP §8 | Buckets with uniform-bucket-level-access disabled; buckets without access logging |
| **Cloud SQL** | SQL instances — SSL, backups, authorized networks | GDPR Art. 32 (security of processing), DORA Art. 9 | Instances without SSL enforcement; backup retention below threshold; `0.0.0.0/0` authorized network |
| **BigQuery** | Datasets and tables — IAM, encryption, expiry | GDPR Art. 5(1)(e) (storage limitation), GDPR Art. 32 | Datasets with allUsers/allAuthenticatedUsers access; tables without expiry on personal-data datasets |

Rule coverage extends to GDPR, DPDP (India's Digital Personal Data Protection Act 2023), and DORA
(EU Digital Operational Resilience Act). The agent does not claim compliance status — it surfaces
posture gaps for your compliance and legal team to review.

## Running a scan

### Scheduled scans

Cloud Scheduler triggers the agent automatically on the cron schedule set via `scan_schedule`
(default: daily at 03:00 UTC). No action required after `terraform apply`.

Verify the job is enabled:

```bash
gcloud scheduler jobs describe \
  "$(terraform output -raw scheduler_job_name)" \
  --location="$(terraform output -raw gcp_region 2>/dev/null || echo us-central1)"
# Expected: State: ENABLED
```

### Manual scan trigger

Trigger an on-demand scan using the Cloud Run service URL:

```bash
SERVICE_URL="$(terraform output -raw agent_service_url)"

gcloud run services proxy "$(terraform output -raw scheduler_job_name)" --port=8080 &
# OR use gcloud identity tokens directly:

TOKEN="$(gcloud auth print-identity-token)"
curl -X POST "${SERVICE_URL}/scan" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json"
```

Signed scan artifacts appear in your GCS bucket under
`gs://<artifact_store_bucket>/juro/<engagement_slug>/`.

### Verify a scan artifact

```bash
juro verify gs://<artifact_store_bucket>/juro/<engagement_slug>/<artifact>.juro
```

Each artifact carries an Ed25519 signature. `juro verify` checks the signature against the published
public key and prints the finding set in plain text.

## Workload Identity and authentication

The agent service account is created inside the customer's GCP project and runs as the Cloud Run
service identity. It holds a read-only custom role (`juroCompliantTier3Agent`) scoped to the project.
The agent authenticates exclusively via Cloud Run Workload Identity tokens — no service account key
is ever issued or stored. Tokens are short-lived and scoped to the duration of a single scan
invocation. Juro's infrastructure has no standing access to the customer project at any point.

## What the scanner reads

The agent's custom role grants read-only access to the following APIs. No write or delete permissions
are granted.

**IAM**
- `iam.roles.get/list`, `iam.serviceAccounts.get/list/getIamPolicy`, `iam.serviceAccountKeys.list`
- `resourcemanager.projects.get/getIamPolicy`

**Cloud Storage**
- `storage.buckets.get/list/getIamPolicy`

**Cloud SQL**
- `cloudsql.instances.get/list`, `cloudsql.databases.get/list`, `cloudsql.backupRuns.list`,
  `cloudsql.users.list`

**BigQuery**
- `bigquery.datasets.get/list/getIamPolicy`, `bigquery.tables.get/list/getIamPolicy`,
  `bigquery.routines.list`

**Logging**
- `logging.sinks.get/list`, `logging.buckets.get/list`, `logging.logMetrics.get/list`,
  `logging.exclusions.get/list`

**Compute / Networking**
- `compute.instances.get/list/getIamPolicy`, `compute.firewalls.get/list`,
  `compute.networks.get/list`, `compute.subnetworks.get/list`, `compute.disks.get/list`,
  `compute.snapshots.get/list`, `compute.routers.get/list`, `compute.routes.get/list`,
  `compute.sslCertificates.get/list`, `compute.targetHttpsProxies.get/list`,
  `compute.urlMaps.get/list`

**GKE**
- `container.clusters.get/list`, `container.nodePools.get/list`, `container.operations.get/list`

**Cloud Run**
- `run.services.get/list/getIamPolicy`, `run.revisions.get/list`, `run.jobs.get/list`

**Pub/Sub, Cloud Functions, Spanner, AlloyDB, Bigtable, Datastore, API Gateway, Cloud KMS,
Secret Manager**
- List and get permissions only (see `main.tf` for the full alphabetically sorted permission set).

**Cloud Asset Inventory**
- `cloudasset.assets.searchAllIamPolicies`, `cloudasset.assets.searchAllResources`

## Non-custodial architecture

The Juro agent is non-custodial by design. Specifically:

- **No customer data leaves the customer's GCP project.** The agent reads GCP resource metadata
  (configuration, IAM policy) and writes signed posture findings to the customer-owned GCS bucket.
  Raw resource content (query results, file contents, log entries) is never read, logged, or
  transmitted.
- **Juro has no inbound access channel.** No SSH, VPN, screen share, or credentials are ever
  provided to Juro. The customer applies this Terraform module from their own CI or workstation.
- **Findings are customer-owned.** The GCS artifact bucket is provisioned and owned by the customer.
  Juro cannot access it. When the engagement ends, `terraform destroy` removes all Juro-managed
  resources; the bucket and its artifacts are retained or deleted per the customer's own policy.
- **Engagement expiry is explicit.** The `expires_at` variable documents the agreed end date.
  Run `terraform destroy -var-file=terraform.tfvars` on or before that date to remove all
  Juro-managed GCP resources.

## License

The Juro agent container image (`ghcr.io/jecertis/cloud-scanner`) is Apache-2.0 licensed.
Rule packs require a commercial subscription. See the SOW and
[`juro-platform/contracts/license-policy.md`](https://github.com/jecertis/juro-platform/blob/main/contracts/license-policy.md)
for terms.
