# Universal Backup Alert Generator (Terraform)

This Terraform module deploys a **Universal Log-Based Alert Policy** for Google Cloud BackupDR. It supports Cloud SQL, Compute Engine, and Persistent Disks.

It uses **Terraform Workspaces** to manage two distinct alert policies (Success & Failure) from a single codebase.

## Features
* **Universal Support:** Automatically detects resource type (SQL, VM, Disk) and location (Region vs Zone).
* **Smart Logic:**
    * **Failure:** Alerts on `FAILED` or `SKIPPED` (ignores `RUNNING`). Extracts specific error messages.
    * **Success:** Alerts only on `SUCCESSFUL`.
* **Dynamic Inputs:** Interactive setup for Project ID, Policy Name, and Notification Channels.
* **Multiple Channels:** Supports sending alerts to multiple destinations (Email, Slack, etc.) simultaneously.

## Prerequisites
1.  **Terraform installed** (v1.3+).
2.  **Google Cloud SDK** (`gcloud`) authenticated.
3.  **Notification Channels** created in the target GCP project.

---

## 🔎 How to Find Notification Channel IDs
Before deploying, you need the IDs of the channels you want to notify (e.g., Email, Slack).

Run this command in your Cloud Shell:
```bash
gcloud beta monitoring channels list --project=YOUR_PROJECT_ID --format="table(displayName, name)"
```

* **Copy the full path** under the NAME column.  
* *Example:* projects/gcbdr-gl/notificationChannels/13703593121157132754

---

## **🚀 Deployment Guide**

### **1. Initialize**

Run this once to download the Google provider.

```bash
terraform init
```

### **2. Deploy the "Failure" Alert**

We use the `failure_alert` workspace for critical notifications.

**Create/Switch Workspace:**
```bash
terraform workspace new failure_alert
# If it already exists: terraform workspace select failure_alert
```

**Deploy Command:** *Replace values below. Use commas (no spaces) for multiple channels.*

```bash
terraform apply \
  -var="project_id=gcbdr-gl" \
  -var="notification_channel_ids=projects/gcbdr-gl/notificationChannels/123...,projects/gcbdr-gl/notificationChannels/456..." \
  -var="alert_condition_type=FAILURE" \
  -var="policy_name=BackupVault Failure Alerts" \
  -var="custom_message=**CRITICAL: BackupVault Failure**"
```

### **3. Deploy the "Success" Alert**

We use the `success_alert` workspace for informational notifications.

**Create/Switch Workspace:**

```bash
terraform workspace new success_alert
# If it already exists: terraform workspace select success_alert

```

**Deploy Command:**

```bash
terraform apply \
  -var="project_id=gcbdr-gl" \
  -var="notification_channel_ids=projects/gcbdr-gl/notificationChannels/123..." \
  -var="alert_condition_type=SUCCESS" \
  -var="policy_name=BackupVault Success Notification" \
  -var="custom_message=**BackupVault Job Successful**"
```

---
## **🛠 Technical Details**

### **Logic Matrix**

| Type | Severity | Filter Logic | Details Extracted |
| :---- | :---- | :---- | :---- |
| **FAILURE** | ERROR | Status != SUCCESSFUL AND Status != RUNNING | jsonPayload.errorMessage |
| **SUCCESS** | (None) | Status == SUCCESSFUL | jsonPayload.jobStatus |

### **Regex Patterns**

* **Resource Name:** .\*/(\[^/\]+)$ (Captures ID from the end of the URL)  
* **Location:** (?:zones|regions)/(\[^/\]+) (Captures either Zone or Region)  
* **Error Message:** EXTRACT(jsonPayload.errorMessage) (Captures exact failure reason)

### **Rate Limiting**

* **Frequency:** Alerts are rate-limited to **one notification every 300 seconds** (5 minutes).  
* **Auto-Close:** Incidents auto-close after 7 days.

---

### 2. Final `main.tf`

This includes the logic fix for `RUNNING` status and the fix for `(null)` location labels.

```hcl
resource "google_monitoring_alert_policy" "dynamic_backup_alert" {
  display_name = var.policy_name
  combiner     = "OR"
  enabled      = true
  project      = var.project_id 

  # Severity Logic: ERROR for Failure, Empty (None) for Success
  severity = var.alert_condition_type == "FAILURE" ? "ERROR" : ""

  user_labels = {
    managed_by = "terraform"
    type       = lower(var.alert_condition_type)
  }

  documentation {
    mime_type = "text/markdown"
    # FORMATTING: Using "Two Spaces + \n" for Markdown line breaks.
    # Using log.extracted_label for location because native resource labels were null.
    content   = "${var.custom_message}  \n**Resource:** $${log.extracted_label.resource_name}  \n**Location:** $${log.extracted_label.location}  \n**Type:** $${log.extracted_label.resource_type}  \n**Project:** $${log.extracted_label.project_id}  \n**Plan:** $${log.extracted_label.backup_plan}  \n**Error/Details:** $${log.extracted_label.details}"
  }

  conditions {
    display_name = "${var.alert_condition_type} Log Match"
    condition_matched_log {
      
      # DYNAMIC FILTER
      # Failure: Status is NOT SUCCESSFUL and NOT RUNNING (to avoid false positives).
      # Success: Status is SUCCESSFUL.
      filter = <<EOT
logName:"bdr_backup_restore_jobs"
jsonPayload.jobCategory=("SCHEDULED_BACKUP" OR "ON_DEMAND_BACKUP")
${var.alert_condition_type == "FAILURE" ? "jsonPayload.jobStatus!=\"SUCCESSFUL\" AND jsonPayload.jobStatus!=\"RUNNING\"" : "jsonPayload.jobStatus=\"SUCCESSFUL\""}
EOT

      label_extractors = {
        # 1. Resource Name: Captures ID from sourceResourceName
        "resource_name" = "REGEXP_EXTRACT(jsonPayload.sourceResourceName, \".*/([^/]+)$\")"
        
        # 2. Location: Captures zone or region (works for both SQL and VM)
        "location"      = "REGEXP_EXTRACT(jsonPayload.sourceResourceName, \"(?:zones|regions)/([^/]+)\")"
        
        # 3. Standard Extractors
        "resource_type" = "EXTRACT(jsonPayload.resourceType)"
        "project_id"    = "REGEXP_EXTRACT(jsonPayload.sourceResourceName, \"projects/([^/]+)/\")"
        "backup_plan"   = "REGEXP_EXTRACT(jsonPayload.backupPlanName, \"backupPlans/([^/]+)$\")"
        
        # 4. Dynamic Details: 
        # Failure: Extracts 'errorMessage' (proven by logs).
        # Success: Extracts 'jobStatus'.
        "details"       = var.alert_condition_type == "FAILURE" ? "EXTRACT(jsonPayload.errorMessage)" : "EXTRACT(jsonPayload.jobStatus)"
      }
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s" # 5 Minute Quiet Period
    }
    auto_close = "604800s" # 7 Days
  }

  # Split string input by comma to allow multiple channels
  notification_channels = [for c in split(",", var.notification_channel_ids) : trimspace(c)]
}
```


### **3. Final variables.tf**

```hcl
variable "project_id" {
  description = ">> QUESTION: What is the GCP Project ID where this alert should be deployed?"
  type        = string
}

variable "notification_channel_ids" {
  description = ">> QUESTION: Notification Channel IDs (comma-separated if multiple)"
  type        = string
}

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
```

### **4. Final versions.tf**
```hcl
terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
  }

  # -------------------------------------------------------------
  # REMOTE BACKEND CONFIGURATION (Best Practice)
  # -------------------------------------------------------------
  # Uncomment the block below and replace 'BUCKET_NAME' with your
  # actual GCS bucket name to store the state securely in the cloud.
  # 
  # backend "gcs" {
  #   bucket  = "my-terraform-state-bucket"
  #   prefix  = "terraform/alerts/state"
  # }
}

provider "google" {
  # We do NOT set the project here so it can be dynamic.
  # Terraform will use the 'project_id' passed in the apply command.
  region  = "us-central1"
}
```

In Google Cloud Storage, the `prefix` acts like a folder path. Without it, Terraform would dump your state file right at the root of the bucket, which gets messy if you use that bucket for other things later.

Here is exactly how that prefix affects your file structure in the bucket, especially since you are using **Workspaces**:

The Folder Structure it Creates
If you use `prefix = "terraform/alerts/state"`, your GCS bucket will look like this:

```shell
my-terraform-state-bucket/
└── terraform/
    └── alerts/
        └── state/
            ├── default.tfstate                 <-- (Default workspace)
            ├── failure_alert/                  <-- (Your Failure Workspace)
            │   └── default.tfstate
            └── success_alert/                  <-- (Your Success Workspace)
                └── default.tfstate
```
**Why I chose that specific name**
`terraform/`: Keeps Terraform files separate from other logs or backups in the same bucket.

`alerts/`: Identifies this specific project. If you later write Terraform code for "Networking" or "IAM", you would use a prefix like terraform/networking/state so they don't overwrite your Alert state.

`state/`: Standard convention to indicate these are state files.

**Can you change it?**
*Yes*. You can change it to anything you want.

* **Short version**: `prefix = "alerts"`
* **Project specific**: `prefix = "gcbdr/prod/alerts"`
