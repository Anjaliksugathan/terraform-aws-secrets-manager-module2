# Terraform AWS Secrets Manager Module

Reusable Terraform module for securely managing AWS Secrets Manager secrets in shared platform environments.

## Problem Statement

Platform teams often face inconsistent secret management:
- Product teams use raw `aws_secretsmanager_secret` resources directly
- No consistent encryption, recovery windows, or access policies
- Difficult to enforce audit trails and rotation policies
- Secrets risk ending up in Terraform state

## Solution

This module provides a **simple reusable abstraction** that:
- Provisions only infrastructure (containers, encryption, policies)
- Keeps ALL secrets out of Terraform state (zero-secrets architecture)
- Supports multi-region replication
- Enforces KMS encryption
- Enables external secret rotation without Terraform involvement

## Design Philosophy

This module intentionally separates infrastructure provisioning from secret value management to avoid exposing application secrets through Terraform state or plan output.

## Key Features

✅ **Zero-secrets architecture** — No secret values in Terraform state or logs  
✅ **KMS encryption** — AWS-managed or customer-managed keys  
✅ **Multi-region replication** — Disaster recovery support  
✅ **Resource policies** — Cross-account and fine-grained access control  
✅ **Automatic rotation** — Lambda-based external rotation  
✅ **Safe deletion** — Recovery window (7-30 days)  

## Quick Start

### Step 1: Provision Secret Container

```hcl
module "app_secret" {
  source = "github.com/Anjaliksugathan/terraform-aws-secrets-manager-module2"

  name                    = "shared/platform/app/db"
  description             = "Database credentials (injected externally)"
  recovery_window_in_days = 7
  replica_regions         = ["eu-central-1"]

  tags = {
    Environment = "prod"
    Team        = "platform"
  }
}

output "db_secret_arn" {
  value = module.app_secret.secret_arn
}
```

Deploy with Terraform:
```bash
terraform init
terraform plan
terraform apply
```

### Step 2: Inject Secrets (Post-Terraform)

**AWS CLI:**
```bash
aws secretsmanager put-secret-value \
  --secret-id shared/platform/app/db \
  --secret-string '{"username":"admin","password":"secure-pass"}'
```

**CI/CD Pipeline (GitHub Actions):**
```yaml
name: Inject Secrets
on: [workflow_dispatch]

jobs:
  inject:
    runs-on: ubuntu-latest
    steps:
      - name: Inject secrets
        run: |
          aws secretsmanager put-secret-value \
            --secret-id shared/platform/app/db \
            --secret-string '{
              "username":"admin",
              "password":"${{ secrets.DB_PASSWORD }}",
              "host":"db.prod.internal"
            }'
```

### Step 3: Applications Retrieve Secrets

**Python:**
```python
import boto3
import json

sm = boto3.client('secretsmanager')
secret = sm.get_secret_value(SecretId='shared/platform/app/db')
db_config = json.loads(secret['SecretString'])

db = psycopg2.connect(
    host=db_config['host'],
    user=db_config['username'],
    password=db_config['password']
)
```

## Module Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `name` | string | - | Yes | Secret name (3+ chars, lowercase) |
| `description` | string | `""` | No | Human-readable description |
| `kms_key_id` | string | `null` | No | KMS key for encryption (default: AWS-managed) |
| `recovery_window_in_days` | number | `7` | No | Recovery window (7-30 days) |
| `replica_regions` | list(string) | `[]` | No | Regions for replication |
| `resource_policy` | string | `null` | No | JSON policy for cross-account access |
| `tags` | map(string) | `{}` | No | Tags for all resources |

## Module Outputs

| Output | Description |
|--------|-------------|
| `secret_arn` | ARN of the secret (for IAM policies, applications) |
| `secret_name` | Name of the secret (for application lookups) |
| `secret_id` | ID of the secret (use for AWS API) |
| `kms_key_id` | KMS key ID used for encryption |

## Security Considerations

### What This Module Prevents

- ❌ Secrets in Terraform state
- ❌ Secrets in `terraform apply` logs
- ❌ Secrets in Terraform plan output
- ❌ Unencrypted secrets in AWS Secrets Manager

### Best Practices

1. **Encrypted remote state** — Use S3 + KMS for state backend
2. **State locking** — Use DynamoDB to prevent concurrent applies
3. **IAM access control** — Restrict who can read secret containers
4. **KMS encryption** — Optional customer-managed keys
5. **Resource policies** — Fine-grained cross-account access
6. **Audit logging** — CloudTrail logs all secret access

## Examples

- `examples/basic/` — Simple secret container with KMS encryption
- `examples/cross-account/` — Cross-account access with resource policies
- `examples/rotation/` — Lambda-based automatic rotation

## Testing

```bash
# Validate configuration
terraform validate

# Plan infrastructure
terraform plan

# Deploy container
terraform apply

# Inject a secret
aws secretsmanager put-secret-value \
  --secret-id $(terraform output -raw secret_name) \
  --secret-string '{"test":"value"}'

# Verify secret exists
aws secretsmanager describe-secret \
  --secret-id $(terraform output -raw secret_name)
```

## Contributing

1. Validate: `terraform validate && terraform fmt -check`
2. Add examples for new features
3. Update README for user-facing changes
4. Keep module focused on infrastructure only (no secret generation/rotation code)

## License

MIT
