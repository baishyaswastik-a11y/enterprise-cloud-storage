# ============================================================
# variables.tf — Single source of truth for all inputs
# One codebase, three environments, zero duplication
# ============================================================

# ──────────────────────────────────────────
# REQUIRED — must be set in .tfvars
# ──────────────────────────────────────────

variable "environment" {
  description = "Deployment environment. Controls defaults for retention, tiering, and redundancy."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be dev, staging, or prod."
  }
}

variable "allowed_account_ids" {
  description = "AWS account IDs permitted to access the bucket. Enforced in bucket policy."
  type        = list(string)
}

variable "data_admin_role_arn" {
  description = "IAM role ARN for data administrators (KMS decrypt access)."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::", var.data_admin_role_arn))
    error_message = "Must be a valid IAM role ARN."
  }
}

# ──────────────────────────────────────────
# OPTIONAL — sensible defaults per purpose
# Override in .tfvars as needed
# ──────────────────────────────────────────

variable "primary_region" {
  description = "Primary AWS region for storage resources."
  type        = string
  default     = "ap-south-1"
}

variable "dr_region" {
  description = "Disaster recovery replica region."
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name — used in resource names and tags."
  type        = string
  default     = "enterprise-data"
}

variable "worm_retention_days" {
  description = <<-EOT
    WORM compliance retention period in days.
    Recommended values:
      dev     = 7    (short for testing — lets you delete test objects)
      staging = 90   (matches typical QA retention policies)
      prod    = 365  (1 year general; use 2555 for 7yr banking/SEBI compliance)
  EOT
  type    = number
  default = 365

  validation {
    condition     = var.worm_retention_days >= 1 && var.worm_retention_days <= 36500
    error_message = "Retention must be between 1 and 36500 days (100 years)."
  }
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for DR. Set false in dev to save costs."
  type        = bool
  default     = true
}

variable "intelligent_tiering_archive_days" {
  description = "Days of inactivity before moving to ARCHIVE_ACCESS tier."
  type        = number
  default     = 90

  validation {
    condition     = var.intelligent_tiering_archive_days >= 90
    error_message = "AWS minimum for ARCHIVE_ACCESS is 90 days."
  }
}

variable "intelligent_tiering_deep_archive_days" {
  description = "Days of inactivity before moving to DEEP_ARCHIVE_ACCESS tier."
  type        = number
  default     = 180

  validation {
    condition     = var.intelligent_tiering_deep_archive_days >= 180
    error_message = "AWS minimum for DEEP_ARCHIVE_ACCESS is 180 days."
  }
}

variable "cloudwatch_alarm_email" {
  description = "Email address for SNS storage alert notifications."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to merge with default tags."
  type        = map(string)
  default     = {}
}
