output "kms_key_id" {
  description = "KMS Unseal vault key ID"
  value       = aws_kms_key.vault_unseal_key.id
}

output "kms_key_arn" {
  description = "KMS Unseal vault key ARN"
  value       = aws_kms_key.vault_unseal_key.arn
}

output "s3_bucket_name" {
  description = "Bucket to hold vault backups"
  value       = aws_s3_bucket.vault_backup_bucket.id
}

output "iam_user_name" {
  description = "IAM User"
  value       = aws_iam_user.vault_kms_user.name
}

output "access_key_id" {
  description = "Access Key"
  value       = aws_iam_access_key.vault_kms_user_access_key.id
}

output "secret_access_key" {
  description = "Secret Access Key"
  value       = aws_iam_access_key.vault_kms_user_access_key.secret
  sensitive   = true
}

