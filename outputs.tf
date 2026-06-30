output "agent_job_name" {
  description = "Cloud Run Job name. Trigger a manual scan with: gcloud run jobs execute <name> --region=<region> --project=<project>"
  value       = google_cloud_run_v2_job.agent.name
}

output "agent_service_account_email" {
  description = "Email of the agent service account. Configure Workload Identity on the Cloud Run service to run as this SA."
  value       = google_service_account.agent.email
}

output "agent_custom_role_id" {
  description = "Fully qualified ID of the agent's custom role (projects/<id>/roles/juroCompliantTier3Agent). Pass to `juro preflight` for permission-hash verification."
  value       = google_project_iam_custom_role.agent.id
}

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job that triggers scans on schedule. Use `gcloud scheduler jobs describe <name>` to verify State=ENABLED."
  value       = google_cloud_scheduler_job.scan_schedule.name
}

output "rule_pack_registry_secret" {
  description = "Secret Manager secret ID storing the rule-pack registry URL."
  value       = google_secret_manager_secret.rule_pack_registry.secret_id
}

output "expires_at" {
  description = "Engagement expiration date — externally enforced."
  value       = var.expires_at
}
