````markdown
# Terraform AWS Secrets Manager Module

**Infrastructure-only Terraform module** for AWS Secrets Manager secret container provisioning. Secret values are injected externally, ensuring **zero secrets in Terraform state**.

## Philosophy

This module enforces a **security-first principle**: Terraform provisions only infrastructure containers and policies—**application secrets are injected and managed by AWS Secrets Manager exclusively**.

### Why This Approach?

**Traditional Approach (Anti-pattern):**
```
Terraform processes secrets
    ↓
Terraform state contains secrets
    ↓
Risk: State exposure = secret exposure
```

**This Module's Approach (Production-Ready):**
```
Terraform
    ↓
Creates only secret container + IAM + KMS
    (NO SECRET VALUES)
    ↓
External system injects secrets directly
    ↓
Applications retrieve from AWS Secrets Manager
    ↓
Result: Zero secrets in Terraform state
```

## Problem Statement

Platform teams need a way to provision AWS Secrets Manager infrastructure while keeping application secrets completely separate from Terraform:

- Infrastructure teams manage containers and policies
- Security teams or automation manage secret values
- Terraform state remains free of sensitive data
- Secrets can be rotated without Terraform involvement
- Clear separation of concerns

## Module Goals

Provide a **reusable, secure abstraction** that:
- Provisions only infrastructure (containers, encryption, policies)
- Keeps ALL secrets out of Terraform state
- Supports multi-region replication
- Enforces KMS encryption
- Provides fine-grained IAM/resource policies
- Enables external rotation without Terraform
- Maintains compliance standards

## Features

- **Zero-secrets architecture** — No secret values in Terraform state or logs
- **KMS encryption** — Optional customer-managed keys
- **Multi-region replication** — Disaster recovery support
- **Resource policies** — Cross-account and fine-grained access control
- **Automatic rotation** — Lambda-based external rotation
- **Recovery window** — Safe deletion window (7-30 days)
- **Simple outputs** — ARN, name, region info (no secrets)

## Usage

### Basic Example: Provision Secret Container

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

# Output: Secret ARN and name for applications to use
output "db_secret_arn" {
  value = module.app_secret.secret_arn
}
```

### Step 1: Deploy with Terraform

```bash
terraform init
terraform plan
terraform apply
```

**Result:** Empty secret container created in AWS Secrets Manager.

### Step 2: Inject Secrets (External to Terraform)

Use **any** of these methods:

#### Option A: AWS CLI (Manual)
```bash
aws secretsmanager put-secret-value \
  --secret-id shared/platform/app/db \
  --secret-string '{"username":"admin","password":"secure-pass"}'
```

#### Option B: Lambda Function
```python
import boto3
import json

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

#### Option C: CI/CD Pipeline (GitHub Actions)
```yaml
name: Inject Secrets

on:
  workflow_dispatch:
  schedule:
    - cron: "0 2 * * 0"  # Weekly

jobs:
  inject:
    runs-on: ubuntu-latest
    steps:
      - name: Inject secrets to AWS Secrets Manager
        env:
          AWS_REGION: eu-west-1
          SECRET_ID: shared/platform/app/db
        run: |
          aws secretsmanager put-secret-value \
            --secret-id $SECRET_ID \
            --region $AWS_REGION \
            --secret-string '{
              "username":"admin",
              "password":"${{ secrets.DB_PASSWORD }}",
              "host":"db.prod.internal"
            }'
```

#### Option D: Kubernetes Secret Operator
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-sm
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-west-1
---
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
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: shared/platform/app/db
        property: username
```

### Step 3: Applications Retrieve Secrets

**Python:**
```python
import boto3

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
import "github.com/aws/aws-sdk-go/service/secretsmanager"

svc := secretsmanager.New(sess)
input := &secretsmanager.GetSecretValueInput{
    SecretId: aws.String("shared/platform/app/db"),
}
result, _ := svc.GetSecretValue(input)
var dbConfig map[string]string
json.Unmarshal([]byte(*result.SecretString), &dbConfig)
```

**Node.js:**
```javascript
const AWS = require('aws-sdk');
const sm = new AWS.SecretsManager();

const secret = await sm.getSecretValue({
  SecretId: 'shared/platform/app/db'
}).promise();

const dbConfig = JSON.parse(secret.SecretString);
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│         Infrastructure Setup (Terraform)             │
├─────────────────────────────────────────────────────┤
│  • aws_secretsmanager_secret (empty container)      │
│  • KMS key (optional)                               │
│  • Resource policies (cross-account access)         │
│  • Rotation configuration (optional Lambda)         │
│  • Multi-region replication                         │
└────────────────┬──────────────────────────────────┘
                 │
                 ↓
    ┌────────────────────────────────┐
    │  AWS Secrets Manager (Empty)   │
    │  arn:aws:secretsmanager:...    │
    └────────────────┬───────────────┘
                     │
    ┌────────────────┴───────────────┐
    │                                 │
    ↓                                 ↓
┌─────────────────┐        ┌──────────────────┐
│   CI/CD Pipe    │        │  Lambda/ETL Job  │
│  (Inject via    │        │  (Fetch from     │
│  GitHub Actions │        │   source system) │
│   AWS CLI)      │        └──────────────────┘
└─────────────────┘
    │                                 │
    └────────────────┬────────────────┘
                     ↓
    ┌────────────────────────────────┐
    │  AWS Secrets Manager (Populated)│
    │  Secret Value: JSON            │
    └────────────────┬───────────────┘
                     │
                     ↓
    ┌────────────────────────────────┐
    │      Applications / Services    │
    │  (Retrieve via IAM permissions) │
    └────────────────────────────────┘
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
| `replica_regions` | list(string) | `[]` | No | Regions to replicate secret to (max 1) |
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

- Secrets in Terraform state
- Secrets in `terraform apply` logs
- Secrets in Terraform plan output
- Unencrypted secrets in AWS Secrets Manager

### Best Practices Implemented

1. **Encrypted remote state** — Still use S3 + KMS even though no secrets present
2. **State locking** — Use DynamoDB to prevent concurrent applies
3. **IAM access control** — Restrict who can read secret containers
4. **KMS encryption** — Optional customer-managed keys
5. **Resource policies** — Fine-grained cross-account access
6. **Audit logging** — CloudTrail logs all secret access

### External Secret Injection Guidelines

| Method | Best For | Security | Complexity |
|--------|----------|----------|-----------|
| **AWS CLI (manual)** | Bootstrap, testing | Low | Low |
| **Lambda function** | Scheduled rotation | High | Medium |
| **CI/CD pipeline** | Deployment-time secrets | High | Medium |
| **External secrets operator** | Kubernetes/container | High | High |
| **CloudFormation custom resources** | IaC integration | Medium | High |

## Examples

- `examples/basic/` — Simple secret container with KMS encryption
- `examples/cross-account/` — Cross-account access with resource policies
- `examples/rotation/` — Lambda-based automatic rotation
- `examples/secret-injection/` — External secret injection patterns

## Testing

```bash
# Validate configuration
terraform validate
terraform fmt -check

# Plan infrastructure
terraform plan

# Deploy container
terraform apply

# Manually inject a secret (example)
aws secretsmanager put-secret-value \
  --secret-id $(terraform output -raw secret_name) \
  --secret-string '{"test":"value"}'

# Verify secret exists (value not visible by default)
aws secretsmanager describe-secret \
  --secret-id $(terraform output -raw secret_name)
```

## Migration Guide

If migrating from a **secret-handling module** (e.g., Vault integration):

1. **Export existing secrets** from old source
   ```bash
   # From Vault
   vault kv get -format=json secret/prod/db > secrets.json
   ```

2. **Deploy this module** for infrastructure
   ```bash
   terraform apply
   ```

3. **Inject secrets** using external tool
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id shared/platform/db \
     --secret-string "$(cat secrets.json | jq -r '.data.data | tojsonstream')"
   ```

4. **Update applications** to retrieve from AWS Secrets Manager instead of old source

5. **Clean up** old infrastructure (remove Vault secret data source, etc.)

## Contributing

1. Validate: `terraform validate && terraform fmt -check`
2. Add examples for new features
3. Update README for user-facing changes
4. No secret-related features — keep module focused on infrastructure only

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

## License

MIT
````
