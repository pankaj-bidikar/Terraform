# --- DYNAMIC PROJECT SETTINGS ---

variable "project_id" {
  description = ">> QUESTION: What is the GCP Project ID where this alert should be deployed?"
  type        = string
}
variable "notification_channel_ids" {
  description = ">> QUESTION: Paste the Notification Channel ID (just the path)"
  type        = string # Changed from list(string)
}

# --- ALERT CONFIGURATION ---

variable "alert_condition_type" {
  description = ">> QUESTION: Is this a 'SUCCESS' or 'FAILURE' alert?"
  type        = string

  validation {
    condition     = contains(["SUCCESS", "FAILURE"], var.alert_condition_type)
    error_message = "Please type exactly 'SUCCESS' or 'FAILURE'."
  }
}

variable "policy_name" {
  description = ">> QUESTION: What is the Name of this Alert Policy?"
  type        = string
}

variable "custom_message" {
  description = ">> QUESTION: Enter the header message (e.g. **BackupVault**)"
  type        = string
}