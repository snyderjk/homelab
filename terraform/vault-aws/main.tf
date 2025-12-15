data "aws_caller_identity" "current" {}

locals {
  # Get current AWS account ID for unique bucket naming
  account_id = data.aws_caller_identity.current.account_id

  # Tags applied to all resources for organization and cost tracking
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
