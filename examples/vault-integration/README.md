# HashiCorp Vault Integration Example

Demonstrates using the Terraform AWS Secrets Manager module with **HashiCorp Vault** as the secret source.

## Prerequisites

- HashiCorp Vault server running and accessible
- Vault KV v2 secret engine enabled at `secret/`
- AWS credentials configured
- Terraform >= 1.0

## Quick Start

### 1. Store Secret in Vault

```bash
vault login
vault kv put secret/prod/postgres \
  username="postgres" \
  password="your-secure-password" \
  host="db.example.com" \
  port="5432"
```

### 2. Set Environment Variables

```bash
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="hvs.xxxxx"
```

### 3. Deploy

```hcl
module "db_secret" {
  source = "../../"

  name = "shared/platform/postgres/credentials"

  use_vault_source  = true
  vault_addr        = var.vault_addr
  vault_token       = var.vault_token
  vault_secret_path = "secret/data/prod/postgres"
  vault_kv_version  = 2

  replica_regions = ["eu-central-1"]

  tags = {
    Environment = "prod"
  }
}
```

```bash
terraform init
terraform plan
terraform apply
```

## How It Works

1. Terraform authenticates with Vault using the provided token
2. Fetches the secret from `secret/data/prod/postgres` (KV v2 path)
3. Injects into AWS Secrets Manager in a single API call
4. Tags with `Source: vault` for audit trail

## Vault KV Versions

**KV v2 (Recommended):**
```hcl
vault_secret_path = "secret/data/prod/postgres"
vault_kv_version  = 2
```

**KV v1:**
```hcl
vault_secret_path = "secret/prod/postgres"
vault_kv_version  = 1
```

## CI/CD: AppRole Authentication

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

## Verify Deployment

```bash
aws secretsmanager get-secret-value \
  --secret-id shared/platform/postgres/credentials \
  --region eu-west-1 | jq '.SecretString | fromjson'
```

## Troubleshooting

**Permission denied:**
- Ensure Vault token has read permissions on the secret path

**Secret not found:**
- Verify: `vault kv get secret/prod/postgres`
- Check KV version: `vault secrets list -detailed`

## Security Best Practices

1. Never commit `VAULT_TOKEN` — use environment variables
2. Use AppRole for CI/CD instead of static tokens
3. Rotate Vault tokens regularly
4. Enable Vault audit logging
5. Use encrypted remote state (S3 + KMS)
6. Restrict IAM access to state backend
