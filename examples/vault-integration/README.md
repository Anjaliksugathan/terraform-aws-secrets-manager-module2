# Vault Integration Example

This example demonstrates how to use the Terraform AWS Secrets Manager module with **HashiCorp Vault** as the secret source.

## Prerequisites

1. **HashiCorp Vault** server running and accessible
2. **Vault KV v2** secret engine enabled at `secret/`
3. **AWS credentials** configured (via AWS CLI, environment variables, or IAM role)
4. **Terraform** >= 1.0

## Setup

### Step 1: Store Secrets in Vault

```bash
# Login to Vault
vault login

# Create a secret with database credentials
vault kv put secret/prod/postgres \
  username="postgres" \
  password="your-secure-password" \
  engine="postgres" \
  host="db.example.com" \
  port="5432" \
  database="myapp"

# Verify the secret
vault kv get secret/prod/postgres
```

### Step 2: Set Environment Variables

```bash
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="hvs.xxxxx"  # Your Vault token

# Or for production, use AppRole authentication:
export VAULT_ROLE_ID="your-role-id"
export VAULT_SECRET_ID="your-secret-id"
```

### Step 3: Create terraform.tfvars

```hcl
aws_region   = "eu-west-1"
environment  = "prod"
secret_name  = "shared/platform/postgres/credentials"
vault_addr   = "https://vault.example.com:8200"
# vault_token is read from VAULT_TOKEN environment variable

# Optional: Enable rotation
enable_rotation     = true
rotation_lambda_arn = "arn:aws:lambda:eu-west-1:123456789:function:rotate-secret"
rotation_days       = 30
```

### Step 4: Deploy

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy (secrets are fetched from Vault and injected into AWS Secrets Manager)
terraform apply
```

## How It Works

1. **Terraform authenticates** with Vault using the provided token
2. **Fetches the secret** from `secret/data/prod/postgres` (KV v2 path)
3. **Parses the secret** into key-value pairs
4. **Injects the secrets** into AWS Secrets Manager in a single API call
5. **Tags the secret** with `Source: vault` for audit trail

## Advantages

✅ **Centralized management** — All secrets stored in Vault
✅ **One-shot deployment** — Single `terraform apply` command
✅ **No manual secret passing** — No need to export sensitive values
✅ **Audit trail** — Every secret access logged in Vault
✅ **Multi-region support** — Secrets replicated across regions
✅ **KMS encryption** — Optional AWS KMS key for encryption
✅ **Automatic rotation** — Optional Lambda-based rotation

## Vault KV Versions

### KV v2 (Recommended)
- Secret path: `secret/data/prod/postgres`
- More features (versioning, metadata)
- Default in most Vault installations

```hcl
vault_secret_path = "secret/data/prod/postgres"
vault_kv_version  = 2
```

### KV v1
- Secret path: `secret/prod/postgres`
- Simpler structure, no versioning

```hcl
vault_secret_path = "secret/prod/postgres"
vault_kv_version  = 1
```

## AppRole Authentication (Recommended for CI/CD)

For automated deployments, use Vault AppRole instead of static tokens:

```hcl
provider "vault" {
  address = var.vault_addr

  auth_login {
    path = "auth/approle/login"

    parameters = {
      role_id   = var.vault_role_id
      secret_id = var.vault_secret_id
    }
  }
}
```

## Verifying the Deployment

```bash
# Check the secret in AWS Secrets Manager
aws secretsmanager describe-secret \
  --secret-id shared/platform/postgres/credentials \
  --region eu-west-1

# Retrieve the secret value
aws secretsmanager get-secret-value \
  --secret-id shared/platform/postgres/credentials \
  --region eu-west-1 | jq '.SecretString | fromjson'
```

## Troubleshooting

### "Error reading secret: permission denied"
- Ensure your Vault token has read permissions on the secret path
- Check Vault audit logs: `vault audit list` and `vault audit enable file file_path=/tmp/vault-audit.log`

### "Secret path not found"
- Verify the secret exists: `vault kv get secret/prod/postgres`
- Check KV version: `vault secrets list -detailed`
- Adjust `vault_secret_path` accordingly

### "Invalid JSON in secret"
- Ensure all values in the Vault secret are simple strings
- Nested objects are not supported

### "Terraform state contains secrets"
- Use an encrypted remote state backend
- Apply `terraform state lock` with DynamoDB
- Restrict IAM access to the state bucket

## Security Best Practices

1. **Never commit VAULT_TOKEN** — Use environment variables
2. **Use AppRole for automation** — More secure than static tokens
3. **Rotate Vault tokens** — Implement a regular rotation schedule
4. **Enable Vault audit logging** — Track all secret access
5. **Use encrypted state backend** — S3 + KMS
6. **Implement state locking** — DynamoDB
7. **Restrict IAM permissions** — Least privilege principle

## Cleanup

```bash
# Destroy AWS resources
terraform destroy

# Optionally delete the secret from Vault
vault kv delete secret/prod/postgres
```

## Advanced: Multiple Secrets with Loop

```hcl
locals {
  secrets = {
    postgres = {
      name      = "shared/platform/postgres"
      path      = "secret/data/prod/postgres"
    }
    mysql = {
      name      = "shared/platform/mysql"
      path      = "secret/data/prod/mysql"
    }
  }
}

module "database_secrets" {
  for_each = local.secrets
  source   = "../../"

  name        = each.value.name
  description = "${each.key} database credentials from Vault"

  use_vault_source  = true
  vault_addr        = var.vault_addr
  vault_token       = var.vault_token
  vault_secret_path = each.value.path
  vault_kv_version  = 2

  tags = {
    Environment = var.environment
    Database    = each.key
  }
}

output "secret_arns" {
  value = {
    for name, secret in module.database_secrets :
    name => secret.secret_arn
  }
}
```

## Next Steps

- Integrate with CI/CD pipeline (GitHub Actions, GitLab CI, Jenkins)
- Set up automatic secret rotation with Lambda
- Enable Vault audit logging for compliance
- Implement cross-account access with resource policies
