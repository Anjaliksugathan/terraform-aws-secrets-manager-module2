# Terraform AWS Secrets Manager Module

Reusable Terraform module for securely managing AWS Secrets Manager secrets in shared platform environments.
This module is intended as a reusable Terraform building block for shared AWS environments managed by infrastructure/platform engineering teams.

## Problem Statement

Platform teams often face inconsistent secret management across infrastructure:

* Product teams use raw `aws_secretsmanager_secret` resources directly
* No consistent encryption, recovery windows, or access policies
* Manual IAM policy management for each secret
* Duplicated configuration across multiple services
* Difficult to enforce audit trails or rotation policies

## Module Goals

Provide a **reusable abstraction** that enforces:
- Secure defaults (KMS encryption, 7-day recovery window)
- Consistent IAM policies and resource access control
- Optional secret sourcing from external vaults (Vault, KeyVault)
- Multi-region replication for disaster recovery
- Optional Lambda-based rotation support
- Centralized standards without limiting flexibility

## Features

- **Secure defaults** — KMS encryption, 7-day recovery window
- **Flexible secret sources** — Direct input or HashiCorp Vault integration
- **Provisioning-time injection** — Retrieve secrets from Vault during terraform apply
- **Resource policies** — Cross-account and fine-grained access control
- **Replica region support** — Multi-region disaster recovery
- **Optional rotation** — External Lambda-based rotation protocol
- **Terraform validation** — Input validation with clear error messages

## Usage

### Option 1: Direct Secret Input

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
Warning:
Terraform may process and store secret values in state when using direct input mode. This approach should only be used for bootstrap or migration scenarios.

For shared platform environments, external secret sources such as HashiCorp Vault are recommended.

### Option 2: HashiCorp Vault Integration

```hcl
module "db_secret" {
  source = "github.com/anjusugathan5/terraform-aws-secrets-manager-module"

  name = "shared/platform/postgres/credentials"

  use_vault_source  = true
  vault_addr        = var.vault_addr
  vault_token       = var.vault_token
  vault_secret_path = "secret/data/prod/postgres"
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
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="hvs.xxxxx"

terraform apply
```

See `examples/vault-integration/` for detailed setup.

## Architecture

```
External Secret Source (Vault / Direct Input)
                    ↓
            Terraform Module
                    ↓
 AWS Secrets Manager (KMS encrypted)
                    ↓
 Applications / Services (IAM-controlled access)
```

The module acts as a **control point** for secret provisioning:
- Centralizes security policies
- Enforces encryption and access patterns
- Provides audit trail via tags and resource policies
- Allows consistent cross-account access

## Security Considerations

### State Management (Important)

When using **direct input**, Terraform processes secret values during `terraform apply`. This means:
- ⚠️ State files may temporarily contain secret values
- ⚠️ Terraform apply logs may expose secrets
- ✅ **Mitigations**: Encrypted remote state (S3 + KMS), state locking (DynamoDB), restricted IAM access

### With Vault Integration

- Secrets are fetched during provisioning from a centralized source
- Vault maintains the audit trail for secret access
- Remote state still requires encryption (best practice)

### Recommendations

1. **Use encrypted remote state** — S3 + KMS with bucket versioning
2. **Enable state locking** — DynamoDB for concurrent access control
3. **Restrict IAM access** — Only allow platform team to read state
4. **Never commit `.tfvars` files containing secrets
5. **Enable Vault audit logging** — Track all secret access (if using Vault)

## Rotation Support

Optional Lambda-based rotation is supported. AWS Secrets Manager rotation flow:

1. **CREATE** — Generate new credential
2. **SET** — Update target system
3. **TEST** — Validate credential works
4. **FINISH** — Promote to active

Enable with:

```hcl
module "db_secret" {
  # ... other config ...

  enable_rotation     = true
  rotation_lambda_arn = aws_lambda_function.rotation.arn
  rotation_days       = 30
}
```

## Module Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `name` | string | - | Yes | Secret name (3+ chars, lowercase, hyphens/slashes allowed) |
| `secret_values` | map(string) | `{}` | No | Key/value pairs for the secret (ignored if using Vault) |
| `description` | string | `""` | No | Human-readable description |
| `kms_key_id` | string | `null` | No | KMS key for encryption (default: AWS-managed) |
| `recovery_window_in_days` | number | `7` | No | Recovery window (7-30 days) |
| `enable_rotation` | bool | `false` | No | Enable automatic rotation |
| `rotation_lambda_arn` | string | `null` | No | Lambda ARN for rotation |
| `rotation_days` | number | `30` | No | Rotation interval in days |
| `replica_regions` | list(string) | `[]` | No | Regions to replicate secret to |
| `resource_policy` | string | `null` | No | JSON resource policy for cross-account access |
| `tags` | map(string) | `{}` | No | Tags for all resources |

**Vault Integration:**

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `use_vault_source` | bool | `false` | Enable HashiCorp Vault as secret source |
| `vault_addr` | string | `""` | Vault server address (or use `VAULT_ADDR` env var) |
| `vault_token` | string | `""` | Vault auth token (or use `VAULT_TOKEN` env var) |
| `vault_secret_path` | string | `""` | Path to secret in Vault |
| `vault_kv_version` | number | `2` | Vault KV engine version (1 or 2) |

## Module Outputs

| Output | Description |
|--------|-------------|
| `secret_arn` | ARN of the secret (for IAM policies, Lambda access) |
| `secret_name` | Name of the secret (for application lookups) |
| `secret_version_id` | Current version ID of the secret |
| `source_type` | Source of secrets (`vault`, or `direct`) |

## Architectural Decisions & Tradeoffs

**Why is Vault integration optional?**
- Not all organizations have Vault. Direct input supports teams still maturing their secret management.
- Allows gradual adoption: start direct, migrate to Vault later.

**Why `ignore_changes = [secret_string]`?**
- Prevents Terraform from overwriting externally-rotated secrets.
- Rotation Lambda can update secrets without triggering Terraform state conflicts.

**Why `map(string)` for secrets?**
- Keeps the module flexible for different formats (JSON, YAML, key-value).
- Applications parse the format they need.

**Why replica regions?**
- Supports disaster recovery scenarios without separate module instantiation.
- Single source of truth for multi-region secret distribution.

**Why `resource_policy` support?**
- Enables cross-account secret access in shared infrastructure scenarios.
- Avoids duplicating secrets across accounts.

## Limitations

- Rotation requires external Lambda — not bundled to keep the module focused
- Cross-account access requires manual policy configuration
- Vault credentials must be available at Terraform runtime
- Doesn't support advanced Vault features (dynamic secrets, SSH) — extensible with custom data sources

## Examples

- `basic/` — Direct secret input
- `vault-integration/` — HashiCorp Vault integration (KV v1 & v2)

## Testing

```bash
terraform validate
terraform fmt -check
terraform plan
terraform apply
```

Verify the secret:
```bash
aws secretsmanager get-secret-value --secret-id shared/platform/app/db | jq .SecretString
```

## Contributing

1. Validate: `terraform validate && terraform fmt -check`
2. Add examples for new features
3. Update README for user-facing changes

## License

MIT
