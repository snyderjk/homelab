resource "aws_kms_key" "vault_unseal_key" {
  description             = "KMS key to unseal vault hosted on on-prem homelab kubernetes cluster"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_in_days

  tags = local.common_tags
}

resource "aws_kms_alias" "homelab_vault_key_alias" {
  name          = "alias/vault-${var.project_name}-unseal"
  target_key_id = aws_kms_key.vault_unseal_key.key_id
}
