# Terraform AWS Secrets Manager Module

Reusable Terraform module for securely managing AWS Secrets Manager secrets.

## Features

- **Secure defaults** — KMS encryption, 7-day recovery window
- **Runtime secret injection** — No hardcoded secrets in code or state
- **Optional rotation support** — External Lambda-based rotation protocol
- **Replica region support** — Multi-region disaster recovery
- **Resource policies** — Cross-account and fine-grained access control
- **Terraform validation** — Input validation and error messages

## Usage

```hcl
module "app_secret" {
  source = "github.com/anjusugathan5/terraform-aws-secrets-manager-module"

  name = "shared/platform/app/db"

  secret_values = {
    username = var.db_username
    password = var.db_password
  }

  replica_regions = ["eu-central-1"]

  tags = {
    Environment = "prod"
    Team        = "platform"
  }
}
```

## Secure Secret Injection

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
  secret_values = var.secret_values

  enable_rotation     = true
  rotation_lambda_arn = aws_lambda_function.rotation.arn
  rotation_days       = 30
}
```

## Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `name` | string | - | Yes | Secret name (3+ chars, lowercase, hyphens/slashes allowed) |
| `secret_values` | map(string) | - | Yes | Key/value pairs for the secret |
| `description` | string | `""` | No | Human-readable description |
| `kms_key_id` | string | `null` | No | KMS key for encryption (default: AWS-managed) |
| `recovery_window_in_days` | number | `7` | No | Recovery window (7-30 days) |
| `enable_rotation` | bool | `false` | No | Enable automatic rotation |
| `rotation_lambda_arn` | string | `null` | No | Lambda ARN for rotation |
| `rotation_days` | number | `30` | No | Rotation interval in days |
| `replica_regions` | list(string) | `[]` | No | Regions to replicate secret to |
| `resource_policy` | string | `null` | No | JSON resource policy for cross-account access |
| `tags` | map(string) | `{}` | No | Tags for all resources |

## Outputs

| Output | Description |
|--------|-------------|
| `secret_arn` | ARN of the secret |
| `secret_name` | Name of the secret |
| `secret_version_id` | Current version ID |

## Design Decisions

- **Rotation is optional** to avoid opinionated defaults — teams implement their own strategy
- **`ignore_changes = [secret_string]`** prevents overwriting rotated secrets
- **`map(string)` for secrets** keeps the module flexible for different formats
- **Replica regions** support disaster recovery scenarios

## Testing

```bash
# Validate configuration
terraform validate
terraform fmt -check

# Deploy example
export TF_VAR_secret_values='{
  "username": "admin",
  "password": "secure-password"
}'
terraform plan
terraform apply

# Verify secret
aws secretsmanager describe-secret --secret-id shared/platform/app/db
aws secretsmanager get-secret-value --secret-id shared/platform/app/db
```

## Limitations

- No automatic password generation — secrets must be provided by caller
- Rotation requires external Lambda — not bundled to keep the module simple
- Cross-account access requires manual policy configuration

## Contributing

1. Test locally: `terraform validate && terraform plan`
2. Format: `terraform fmt`
3. Add tests to `examples/` for new features
4. Update README for user-facing changes

## License

MIT
