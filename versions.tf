terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
  }

  # --- NEW BACKEND CONFIGURATION ---
  backend "gcs" {
    bucket = "my-terraform-state-bucket-99" # REPLACE with your actual bucket name
    prefix = "terraform/state"              # A folder name inside the bucket
  }
}

provider "google" {
  # project = var.project_id (removed to allow dynamic input)
  region = "us-central1"
}