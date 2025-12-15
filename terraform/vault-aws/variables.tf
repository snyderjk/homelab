variable "project_name" {
  description = "Project Name"
  type        = string
}

variable "environment" {
  description = "environment for the deployed resources"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be in dev, staging, or prod"
  }
}

variable "kms_deletion_window_in_days" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30
  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "Deletion window must be between 7 and 30 days"
  }
}

variable "s3_lifecycle_days" {
  description = "Number of days to retain S3 backup snapshots"
  type        = number
  default     = 30
}
