# ---------------------------------------------------------
# UNIVERSAL BACKUP ALERT POLICY (SQL, GCE, DISK)
# ---------------------------------------------------------

resource "google_monitoring_alert_policy" "dynamic_backup_alert" {
  display_name = var.policy_name
  combiner     = "OR"
  enabled      = true
  project      = var.project_id # Dynamic Project ID

  # Severity Logic: ERROR for Failure, Empty (None) for Success
  severity = var.alert_condition_type == "FAILURE" ? "ERROR" : ""

  user_labels = {
    managed_by = "terraform"
    type       = lower(var.alert_condition_type)
  }

  documentation {
    mime_type = "text/markdown"
    # REVERTED: Switched back to log.extracted_label.location since the native labels were null.
    content = "${var.custom_message}  \n**Resource:** $${log.extracted_label.resource_name}  \n**Location:** $${log.extracted_label.location}  \n**Type:** $${log.extracted_label.resource_type}  \n**Project:** $${log.extracted_label.project_id}  \n**Plan:** $${log.extracted_label.backup_plan}  \n**Error/Details:** $${log.extracted_label.details}"
  }

  conditions {
    display_name = "${var.alert_condition_type} Log Match"
    condition_matched_log {

      # FIXED FILTER LOGIC
      # Failure Mode: Status is NOT Successful AND Status is NOT Running.
      # Success Mode: Status IS Successful.
      filter = <<EOT
logName:"bdr_backup_restore_jobs"
jsonPayload.jobCategory=("SCHEDULED_BACKUP" OR "ON_DEMAND_BACKUP" OR "RESTORE")
${var.alert_condition_type == "FAILURE" ? "jsonPayload.jobStatus!=\"SUCCESSFUL\" AND jsonPayload.jobStatus!=\"RUNNING\"" : "jsonPayload.jobStatus=\"SUCCESSFUL\""}
EOT

      label_extractors = {
        # 1. Resource Name (Working)
        "resource_name" = "REGEXP_EXTRACT(jsonPayload.sourceResourceName, \".*/([^/]+)$\")"

        # 2. Location (Working - confirmed by your screenshot)
        "location" = "REGEXP_EXTRACT(jsonPayload.sourceResourceName, \"(?:zones|regions)/([^/]+)\")"

        # 3. Standard Fields
        "resource_type" = "EXTRACT(jsonPayload.resourceType)"
        "project_id"    = "REGEXP_EXTRACT(jsonPayload.sourceResourceName, \"projects/([^/]+)/\")"
        "backup_plan"   = "REGEXP_EXTRACT(jsonPayload.backupPlanName, \"backupPlans/([^/]+)$\")"

        # 4. FIXED DETAILS: targeting 'jsonPayload.errorMessage' as proven by your JSON
        "details" = var.alert_condition_type == "FAILURE" ? "EXTRACT(jsonPayload.errorMessage)" : "EXTRACT(jsonPayload.jobStatus)"
      }
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    auto_close = "604800s" # 7 Days
  }

  # New code: Splits the string by commas and removes accidental spaces
  notification_channels = [for c in split(",", var.notification_channel_ids) : trimspace(c)]
}