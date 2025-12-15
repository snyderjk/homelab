# Vault AWS Infrastructure

Terraform configuration for AWS resources required by HashiCorp Vault running in homelab Kubernetes cluster.

## Overview

This Terraform project provisions the AWS infrastructure needed for Vault's KMS auto-unseal and S3 backup capabilities:

- **KMS Key**: Used for Vault auto-unseal (eliminates manual unseal on pod restarts)
- **S3 Bucket**: Stores automated Raft snapshot backups
- **IAM User**: Provides programmatic access for Vault to AWS services
- **IAM Policies**: Least-privilege permissions for KMS and S3 operations

## Architecture
```
Homelab Kubernetes Cluster
    ↓
Vault Pods (on-prem)
    ↓
AWS IAM User Credentials (in K8s Secret)
    ↓
AWS KMS (auto-unseal) + S3 (backups)
```

This hybrid architecture keeps compute costs zero (homelab) while using AWS as a trust anchor for secrets management.

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with appropriate credentials
- Existing S3 bucket for Terraform state: `snyderjk-terraform-state-files`
- Existing DynamoDB table for state locking: `terraform-statefile-locks`

## Usage

### Initial Deployment

1. **Clone the repository and navigate to this directory:**
```bash
   cd terraform/vault-aws
```

2. **Create `terraform.tfvars` with your values:**
```hcl
   project_name = "homelab-vault"
   environment  = "dev"
```

3. **Initialize Terraform:**
```bash
   terraform init
```

4. **Review the plan:**
```bash
   terraform plan
```

5. **Apply the configuration:**
```bash
   terraform apply
```

6. **Save the outputs (IMPORTANT):**
```bash
   # Display all outputs
   terraform output
   
   # Save the secret access key to your password manager
   terraform output -raw secret_access_key
```

   ⚠️ **CRITICAL**: The secret access key is only available via Terraform output. Save it immediately to a secure password manager (Bitwarden, 1Password, etc.).

### Outputs

After successful apply, you'll get:

- `kms_key_id` - KMS key ID for Vault configuration
- `kms_key_arn` - KMS key ARN for reference
- `s3_bucket_name` - S3 bucket name for backup configuration
- `iam_user_name` - IAM user name for documentation
- `access_key_id` - AWS access key ID for Kubernetes secret
- `secret_access_key` - AWS secret access key (sensitive, for Kubernetes secret)

### Next Steps

After deploying this infrastructure:

1. Create Kubernetes secret with AWS credentials:
```bash
   kubectl create namespace vault
   kubectl create secret generic vault-aws-creds -n vault \
     --from-literal=AWS_ACCESS_KEY_ID=<access_key_id> \
     --from-literal=AWS_SECRET_ACCESS_KEY=<secret_access_key> \
     --from-literal=AWS_REGION=us-east-1
```

2. Deploy Vault via GitOps (see `kubernetes/infrastructure/vault/`)

3. Configure Vault to use KMS auto-unseal (documented in Vault HelmRelease)

## Configuration

### Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_name` | Project name used in resource naming | (required) |
| `environment` | Environment (dev/staging/prod) | `"dev"` |
| `kms_deletion_window_in_days` | KMS key deletion window | `30` |
| `s3_lifecycle_days` | S3 backup retention in days | `30` |

### File Structure
```
terraform/vault-aws/
├── provider.tf          # AWS provider configuration
├── backend.tf           # S3 backend for state storage
├── variables.tf         # Input variable definitions
├── terraform.tfvars     # Variable values (gitignored)
├── main.tf              # Data sources and locals
├── kms.tf               # KMS key and alias
├── s3.tf                # S3 bucket configuration
├── iam.tf               # IAM user, policies, and attachments
├── outputs.tf           # Output definitions
└── README.md            # This file
```

## Security Considerations

### Credentials Management

- **Root Secret**: The AWS credentials (access key + secret key) are the "secret zero" for this architecture
- **Storage**: Credentials stored in Kubernetes secret (created manually, not via GitOps)
- **Rotation**: Rotate IAM access keys every 90 days (see runbooks)
- **Least Privilege**: IAM policies limit access to only required KMS key and S3 bucket

### KMS Key Protection

- **Deletion Protection**: 30-day deletion window prevents accidental key loss
- **Key Rotation**: Automatic annual rotation enabled
- **Access Control**: Only the dedicated IAM user can use this key

## Disaster Recovery

### Backup Strategy

- Automated Raft snapshots uploaded to S3 daily (via CronJob)
- 30-day retention (configurable via `s3_lifecycle_days`)
- Versioning enabled for protection against accidental deletion


## Author

Built as part of a DevOps portfolio demonstrating hybrid cloud architecture and infrastructure as code best practices.
