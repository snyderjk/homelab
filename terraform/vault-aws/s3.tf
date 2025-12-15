resource "aws_s3_bucket" "vault_backup_bucket" {
  bucket = "vault-${var.project_name}-backups-${local.account_id}"

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "vault_backup_versioning" {
  bucket = aws_s3_bucket.vault_backup_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vault_backup_encryption" {
  bucket = aws_s3_bucket.vault_backup_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bucket will not be publicly accessible
resource "aws_s3_bucket_public_access_block" "bucket_public_access_config" {
  bucket = aws_s3_bucket.vault_backup_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "vault_backup_lifecycle" {
  bucket = aws_s3_bucket.vault_backup_bucket.id

  rule {
    id     = "delete-old-snapshots"
    status = "Enabled"

    expiration {
      days = var.s3_lifecycle_days
    }
  }
}
