# Terraform AWS Secrets Manager Module

Reusable Terraform module for securely managing AWS Secrets Manager secrets.

## Features

- **Secure defaults** — KMS encryption, 7-day recovery window
- **Multiple secret sources** — Direct input, HashiCorp Vault, Azure Key Vault
- **One-shot injection** — Fetch and inject secrets from external vaults in a single `terraform apply`
- **No manual secret passing** — Integrate with existing Vault/KeyVault infrastructure
- **Optional rotation support** — External Lambda-based rotation protocol
- **Replica region support** — Multi-region disaster recovery
- **Resource policies** — Cross-account and fine-grained access control
- **Terraform validation** — Input validation and error messages

## Why Use External Secret Sources?

### Problems with Direct Secret Injection
❌ Manual environment variables for each deployment
❌ Secrets visible in shell history
❌ Easy to commit secrets accidentally
❌ Doesn't scale with multiple secrets

### Solution: Vault/KeyVault Integration
✅ Centralized secret management
✅ Single `terraform apply` injection
✅ No secrets in state (they're fetched at runtime)
✅ Audit trail in Vault/KeyVault
✅ Supports secret rotation

## Usage

### Option 1: Direct Secret Input (Original Method)

```hcl
module "app_secret" {
  source = "github.com/anjusugathan5/terraform-aws-secrets-manager-module"

  name = "shared/platform/app/db"

  secret_values = {
    username = var.db_username
    password = var.db_password
  }

  tags = {
    Environment = "prod"
    Team        = "platform"
  }
}
```

### Option 2: HashiCorp Vault Integration (RECOMMENDED)

```hcl
module "db_secret" {
  source = "github.com/anjusugathan5/terraform-aws-secrets-manager-module"

  name = "shared/platform/postgres/credentials"

  # Enable Vault integration
  use_vault_source  = true
  vault_addr        = var.vault_addr
  vault_token       = var.vault_token
  vault_secret_path = "secret/data/prod/postgres"  # KV v2
  vault_kv_version  = 2

  replica_regions = ["eu-central-1"]
  
  tags = {
    Environment = "prod"
    Team        = "platform"
  }
}
```

**Setup:**
```bash
# 1. Set Vault credentials (or use environment variables)
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="hvs.xxxxx"

# 2. Ensure secret exists in Vault
vault kv put secret/prod/postgres username=admin password=securepass

# 3. Deploy - secrets are fetched and injected in one shot
terraform apply
```

### Option 3: Azure Key Vault Integration

```hcl
module "app_secret" {
  source = "github.com/anjusugathan5/terraform-aws-secrets-manager-module"

  name = "shared/platform/app/config"

  # Enable Azure Key Vault integration
  use_azure_keyvault_source  = true
  azure_keyvault_id          = data.azurerm_key_vault.this.id
  azure_keyvault_secret_name = "app-credentials"

  tags = {
    Environment = "prod"
    Team        = "platform"
  }
}
```

### Option 4: Hybrid - Vault Base + Local Overrides

```hcl
module "app_secret" {
  source = "github.com/anjusugathan5/terraform-aws-secrets-manager-module"

  name = "shared/platform/app/config"

  use_vault_source  = true
  vault_addr        = var.vault_addr
  vault_token       = var.vault_token
  vault_secret_path = "secret/data/prod/app"

  # Merge additional secrets
  secret_overrides = {
    api_key      = var.runtime_api_key
    feature_flag = "enabled"
  }

  tags = {
    Environment = "prod"
  }
}
```

## Secure Secret Injection

### With Vault/KeyVault - Recommended
No secrets need to be passed via environment variables! Terraform authenticates with Vault/KeyVault using a token or managed identity.

```bash
# All authentication is environment-based or provider config
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="hvs.xxxxx"  # Or use AppRole, JWT, etc.

terraform apply
# Secrets are fetched from Vault and injected into AWS Secrets Manager
```

### Direct Input (Legacy)
**Secrets should NEVER be committed to Git.**

Inject via environment variables:
```bash
export TF_VAR_secret_values='{
  "username": "admin",
  "password": "your-secure-password"
}'
terraform apply
```

Or from GitHub Actions secrets:
```yaml
- name: Deploy secrets
  env:
    TF_VAR_secret_values: ${{ secrets.DB_CREDENTIALS }}
  run: terraform apply
```

## Security Considerations

### With Vault/KeyVault Integration
✅ Secrets never stored in Terraform state
✅ Secrets fetched at deployment time
✅ Centralized audit trail in Vault/KeyVault
✅ Support for secret rotation
✅ No secrets in shell history

### With Direct Injection
Although secrets are stored in AWS Secrets Manager, Terraform state may temporarily contain secret values during plan/apply.

Recommended mitigations:
- Encrypted remote state backend (S3 + KMS)
- Restricted IAM access to state backend
- State locking (DynamoDB)
- Do not commit `.tfvars` files — use environment variables instead

## Rotation Support

Optional Lambda-based rotation is supported. The standard AWS Secrets Manager rotation flow:

1. **CREATE** — Generate new credential
2. **SET** — Update target system
3. **TEST** — Validate credential works
4. **FINISH** — Promote to active

See `examples/rotation_lambda/` for implementation.

```hcl
module "db_secret" {
  source = "..."

  name        = "shared/platform/postgres/credentials"
  use_vault_source  = true
  vault_secret_path = "secret/data/prod/postgres"

  enable_rotation     = true
  rotation_lambda_arn = aws_lambda_function.rotation.arn
  rotation_days       = 30
}
```

## Inputs

### Core Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `name` | string | - | Yes | Secret name (3+ chars, lowercase, hyphens/slashes allowed) |
| `secret_values` | map(string) | `{}` | No | Key/value pairs for the secret (ignored if using Vault/KeyVault) |
| `description` | string | `""` | No | Human-readable description |
| `kms_key_id` | string | `null` | No | KMS key for encryption (default: AWS-managed) |
| `recovery_window_in_days` | number | `7` | No | Recovery window (7-30 days) |
| `enable_rotation` | bool | `false` | No | Enable automatic rotation |
| `rotation_lambda_arn` | string | `null` | No | Lambda ARN for rotation |
| `rotation_days` | number | `30` | No | Rotation interval in days |
| `replica_regions` | list(string) | `[]` | No | Regions to replicate secret to |
| `resource_policy` | string | `null` | No | JSON resource policy for cross-account access |
| `tags` | map(string) | `{}` | No | Tags for all resources |

### Vault Integration Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `use_vault_source` | bool | `false` | No | Enable HashiCorp Vault as secret source |
| `vault_addr` | string | `""` | No | Vault server address (or use `VAULT_ADDR` env var) |
| `vault_token` | string | `""` | No | Vault auth token (or use `VAULT_TOKEN` env var) |
| `vault_secret_path` | string | `""` | No | Path to secret in Vault (`secret/data/prod/db` for KV v2 or `secret/prod/db` for KV v1) |
| `vault_kv_version` | number | `2` | No | Vault KV engine version (1 or 2) |

### Azure Key Vault Integration Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `use_azure_keyvault_source` | bool | `false` | No | Enable Azure Key Vault as secret source |
| `azure_keyvault_id` | string | `""` | No | Azure Key Vault resource ID |
| `azure_keyvault_secret_name` | string | `""` | No | Name of the secret in Azure Key Vault |

## Outputs

| Output | Description |
|--------|-------------|
| `secret_arn` | ARN of the secret (for IAM policies, Lambda access) |
| `secret_name` | Name of the secret (for application lookups) |
| `secret_version_id` | Current version ID of the secret (for debugging) |
| `source_type` | Source of the injected secrets (`vault`, `azure_keyvault`, or `direct`) |

## Design Decisions

- **Vault integration is optional** — allows flexible secret management strategies
- **Multiple source support** — Vault, Azure KeyVault, or direct input
- **`ignore_changes = [secret_string]`** prevents overwriting externally-rotated secrets
- **`map(string)` for secrets** keeps the module flexible for different formats
- **Replica regions** support disaster recovery scenarios
- **One-shot injection** — fetch and inject all secrets in a single `terraform apply`

## Examples

See the `examples/` directory for complete working examples:
- `basic/` — Direct secret input
- `vault-integration/` — HashiCorp Vault integration (KV v1 & v2)
- `azure-keyvault-integration/` — Azure Key Vault integration
- `rotation_lambda/` — Lambda-based secret rotation

## Testing

```bash
# Validate configuration
terraform validate
terraform fmt -check

# Test with Vault integration
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="hvs.xxxxx"
terraform plan
terraform apply

# Verify secret
aws secretsmanager describe-secret --secret-id shared/platform/app/db
aws secretsmanager get-secret-value --secret-id shared/platform/app/db
```

## Limitations

- Rotation requires external Lambda — not bundled to keep the module simple
- Cross-account access requires manual policy configuration
- Vault/KeyVault credentials must be available at Terraform runtime
- Azure Key Vault requires Azure provider authentication

## Security Best Practices

1. **Use Vault AppRole or JWT auth** instead of static tokens:
   ```hcl
   provider "vault" {
     auth_login {
       path = "auth/approle/login"
       parameters = {
         role_id   = var.vault_role_id
         secret_id = var.vault_secret_id
       }
     }
   }
   ```

2. **Encrypt remote state** with S3 + KMS
3. **Use state locking** with DynamoDB
4. **Restrict IAM access** to state backend
5. **Enable audit logging** in Vault/KeyVault
6. **Rotate Vault tokens** regularly

## Contributing

1. Test locally: `terraform validate && terraform plan`
2. Format: `terraform fmt`
3. Add examples for new features
4. Update README for user-facing changes

## License

MIT
