resource "aws_iam_user" "vault_kms_user" {
  name = "vault-${var.project_name}-kms-user"

  tags = local.common_tags
}

data "aws_iam_policy_document" "vault_kms_policy_document" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.vault_unseal_key.arn]
  }
}

data "aws_iam_policy_document" "vault_s3_policy_document" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.vault_backup_bucket.arn}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.vault_backup_bucket.arn]
  }
}

resource "aws_iam_policy" "vault_kms_policy" {
  name        = "vault-${var.project_name}-kms-policy"
  description = "Allow vault to use KMS for auto-unseal"
  policy      = data.aws_iam_policy_document.vault_kms_policy_document.json

  tags = local.common_tags

}

resource "aws_iam_policy" "vault_s3_policy" {
  name        = "vault-${var.project_name}-s3-policy"
  description = "Allow vault to access s3 to perform backup operations"
  policy      = data.aws_iam_policy_document.vault_s3_policy_document.json

  tags = local.common_tags
}

resource "aws_iam_user_policy_attachment" "vault_kms_policy_attachment" {
  user       = aws_iam_user.vault_kms_user.name
  policy_arn = aws_iam_policy.vault_kms_policy.arn
}

resource "aws_iam_user_policy_attachment" "vault_s3_policy_attachment" {
  user       = aws_iam_user.vault_kms_user.name
  policy_arn = aws_iam_policy.vault_s3_policy.arn
}

resource "aws_iam_access_key" "vault_kms_user_access_key" {
  user = aws_iam_user.vault_kms_user.name

}
