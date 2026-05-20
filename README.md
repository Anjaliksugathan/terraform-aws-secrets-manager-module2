# Terraform AWS Secrets Manager Module

Reusable Terraform module for securely managing AWS Secrets Manager secrets in shared platform environments. This module is intended as a reusable Terraform building block for shared AWS environments managed by infrastructure/platform engineering teams.

## Problem Statement

Platform teams often face inconsistent secret management across infrastructure:

- Product teams use raw `aws_secretsmanager_secret` resources directly
- No consistent encryption, recovery windows, or access policies
- Manual IAM policy management for each secret
- Duplicated configuration across multiple services
- Difficult to enforce audit trails or rotation policies

## Solution

This module provides a **simple, reusable abstraction** that:
- Provisions only infrastructure (containers, encryption, policies)
- Keeps ALL secrets out of Terraform state (zero-secrets architecture)
- Supports multi-region replication
- Enforces KMS encryption
- Provides fine-grained IAM and resource-based policies
- Enables external secret rotation without Terraform involvement
- Maintains compliance standards

## Key Features

✅ **Zero-secrets architecture** — No secret values in Terraform state or logs  
✅ **KMS encryption** — AWS-managed or customer-managed keys  
✅ **Multi-region replication** — Disaster recovery support  
✅ **Resource policies** — Cross-account and fine-grained access control  
✅ **Automatic rotation** — Lambda-based external rotation  
✅ **Safe deletion** — Recovery window (7-30 days)  
✅ **Simple outputs** — ARN, name, region info (no secrets)  

## Quick Start

### Step 1: Create Secret Container (Terraform)

```hcl
module "app_secret" {
  source = "github.com/Anjaliksugathan/terraform-aws-secrets-manager-module2"

  name                    = "shared/platform/app/db"
  description             = "Database credentials (injected externally)"
  recovery_window_in_days = 7

  # Optional: Multi-region replication
  replica_regions = ["eu-central-1"]

  # Optional: Custom KMS key
  kms_key_id = aws_kms_key.this.id

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

**Result:** Empty secret container created in AWS Secrets Manager.

### Step 2: Inject Secrets (External to Terraform)

Use **any** of these methods:

#### AWS CLI (Manual)
```bash
aws secretsmanager put-secret-value \
  --secret-id shared/platform/app/db \
  --secret-string '{"username":"admin","password":"secure-pass"}'
```

#### Lambda Function
```python
import boto3, json

sm = boto3.client('secretsmanager')
secret = {
    "username": "postgres_user",
    "password": "generated-secure-password",
    "host": "db.example.com",
    "port": "5432"
}

sm.put_secret_value(
    SecretId='shared/platform/app/db',
    SecretString=json.dumps(secret)
)
```

#### CI/CD Pipeline (GitHub Actions)
```yaml
name: Inject Secrets
on: [workflow_dispatch]

jobs:
  inject:
    runs-on: ubuntu-latest
    steps:
      - name: Inject secrets
        env:
          AWS_REGION: eu-west-1
        run: |
          aws secretsmanager put-secret-value \
            --secret-id shared/platform/app/db \
            --region $AWS_REGION \
            --secret-string '{
              "username":"admin",
              "password":"${{ secrets.DB_PASSWORD }}",
              "host":"db.prod.internal"
            }'
```

#### Kubernetes External Secrets
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-db-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-sm
    kind: SecretStore
  target:
    name: app-db
  data:
    - secretKey: username
      remoteRef:
        key: shared/platform/app/db
        property: username
```

### Step 3: Applications Retrieve Secrets

**Python:**
```python
import boto3, json

sm = boto3.client('secretsmanager')
secret = sm.get_secret_value(SecretId='shared/platform/app/db')
db_config = json.loads(secret['SecretString'])

db = psycopg2.connect(
    host=db_config['host'],
    user=db_config['username'],
    password=db_config['password']
)
```

**Go:**
```go
svc := secretsmanager.New(sess)
result, _ := svc.GetSecretValue(&secretsmanager.GetSecretValueInput{
    SecretId: aws.String("shared/platform/app/db"),
})
var dbConfig map[string]string
json.Unmarshal([]byte(*result.SecretString), &dbConfig)
```

**Node.js:**
```javascript
const sm = new AWS.SecretsManager();

const secret = await sm.getSecretValue({
  SecretId: 'shared/platform/app/db'
}).promise();

const dbConfig = JSON.parse(secret.SecretString);
```

## Module Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `name` | string | - | Yes | Secret name (3+ chars, lowercase, hyphens/slashes allowed) |
| `description` | string | `""` | No | Human-readable description |
| `kms_key_id` | string | `null` | No | KMS key for encryption (default: AWS-managed) |
| `recovery_window_in_days` | number | `7` | No | Recovery window (7-30 days) |
| `enable_rotation` | bool | `false` | No | Enable automatic rotation |
| `rotation_lambda_arn` | string | `null` | No | Lambda ARN for rotation |
| `rotation_days` | number | `30` | No | Rotation interval in days |
| `replica_regions` | list(string) | `[]` | No | Regions to replicate secret to |
| `resource_policy` | string | `null` | No | JSON resource policy for cross-account access |
| `tags` | map(string) | `{}` | No | Tags for all resources |

## Module Outputs

| Output | Description |
|--------|-------------|
| `secret_arn` | ARN of the secret (for IAM policies, applications) |
| `secret_name` | Name of the secret (for application lookups) |
| `secret_id` | ID of the secret (same as name, use for AWS API) |
| `kms_key_id` | KMS key ID used for encryption |
| `replica_regions` | List of replica regions |

## Security Considerations

### What This Module PREVENTS

- ❌ Secrets in Terraform state
- ❌ Secrets in `terraform apply` logs
- ❌ Secrets in Terraform plan output
- ❌ Unencrypted secrets in AWS Secrets Manager

### Best Practices Implemented

1. **Encrypted remote state** — Use S3 + KMS even though no secrets present
2. **State locking** — Use DynamoDB to prevent concurrent applies
3. **IAM access control** — Restrict who can read secret containers
4. **KMS encryption** — Optional customer-managed keys
5. **Resource policies** — Fine-grained cross-account access
6. **Audit logging** — CloudTrail logs all secret access

## Examples

- `examples/basic/` — Simple secret container with KMS encryption
- `examples/cross-account/` — Cross-account access with resource policies
- `examples/rotation/` — Lambda-based automatic rotation
- `examples/secret-injection/` — External secret injection patterns

## Testing

```bash
# Validate configuration
terraform validate

# Plan infrastructure
terraform plan

# Deploy container
terraform apply

# Inject a secret (example)
aws secretsmanager put-secret-value \
  --secret-id $(terraform output -raw secret_name) \
  --secret-string '{"test":"value"}'

# Verify secret exists
aws secretsmanager describe-secret \
  --secret-id $(terraform output -raw secret_name)
```

## Migration Guide

If migrating from another secret-handling system:

1. **Export existing secrets**
2. **Deploy this module** for infrastructure
3. **Inject secrets** using external tool
4. **Update applications** to retrieve from AWS Secrets Manager
5. **Clean up** old infrastructure

## FAQ

**Q: How do I deploy without manually running AWS CLI?**  
A: Use a Lambda function, CI/CD pipeline, or Kubernetes operator (see examples above).

**Q: What if I need secrets at `terraform apply` time?**  
A: This module doesn't support that. Use a separate, temporary secret-injection step after `terraform apply`.

**Q: Can I use this with Terraform workspaces?**  
A: Yes, use different secret names per workspace and inject accordingly.

**Q: Does this support automatic secret generation?**  
A: No, but pair with AWS Lambda or AWS Systems Manager Parameter Store for generation.

**Q: What about secret rotation?**  
A: Configure `enable_rotation` and provide a Lambda ARN. Rotation happens independently of Terraform.

## Contributing

1. Validate: `terraform validate && terraform fmt -check`
2. Add examples for new features
3. Update README for user-facing changes
4. No secret-related features — keep module focused on infrastructure only

## License

MIT
