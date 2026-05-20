````markdown
# Basic Example: Infrastructure-Only Secret Container

This example shows the **simplest possible deployment** of the module:
- Provisions an empty secret container
- No secret values in Terraform
- KMS encryption enabled
- Multi-region replication
- Outputs for applications and IAM policies

## Architecture

```
Terraform apply
    ↓
aws_secretsmanager_secret (empty)
    ↓
External system injects secrets later
    ↓
Applications retrieve
```

## Deployment

```bash
cd examples/basic
terraform init
terraform plan
terraform apply
```

## Outputs

After applying, you'll get:

```
secret_arn  = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:shared/platform/app/db-xxxxx"
secret_name = "shared/platform/app/db"
secret_id   = "shared/platform/app/db"
```

Use these outputs to:

1. **Configure IAM policies** to allow applications to read the secret
2. **Inject secret values** after deployment
3. **Grant access** via resource policies

## Inject Secrets (Post-Deployment)

After Terraform has provisioned the container, inject secrets using one of these methods:

### AWS CLI (Manual)

```bash
aws secretsmanager put-secret-value \
  --secret-id shared/platform/app/db \
  --secret-string '{"username":"postgres_user","password":"secure-password","host":"db.prod.internal"}'
```

### Lambda Function

```python
import boto3
import json

sm = boto3.client('secretsmanager')

secret = {
    "username": os.getenv('DB_USERNAME'),
    "password": os.getenv('DB_PASSWORD'),
    "host": os.getenv('DB_HOST'),
    "port": "5432"
}

sm.put_secret_value(
    SecretId='shared/platform/app/db',
    SecretString=json.dumps(secret)
)
```

### CI/CD Pipeline (GitHub Actions)

```yaml
name: Inject Secrets

on:
  workflow_dispatch:

jobs:
  inject:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: eu-west-1

      - name: Inject secrets
        run: |
          aws secretsmanager put-secret-value \
            --secret-id shared/platform/app/db \
            --secret-string '{
              "username":"admin",
              "password":"${{ secrets.DB_PASSWORD }}",
              "host":"db.example.com"
            }'
```

## Applications Retrieve Secrets

Once injected, applications retrieve the secret from AWS Secrets Manager:

### Python

```python
import boto3
import json

sm = boto3.client('secretsmanager')
secret = sm.get_secret_value(SecretId='shared/platform/app/db')
db_config = json.loads(secret['SecretString'])

# Use credentials
db = psycopg2.connect(
    host=db_config['host'],
    user=db_config['username'],
    password=db_config['password'],
    port=db_config['port']
)
```

### Go

```go
import (
    "github.com/aws/aws-sdk-go/service/secretsmanager"
    "encoding/json"
)

svc := secretsmanager.New(sess)
input := &secretsmanager.GetSecretValueInput{
    SecretId: aws.String("shared/platform/app/db"),
}
result, _ := svc.GetSecretValue(input)
var dbConfig map[string]string
json.Unmarshal([]byte(*result.SecretString), &dbConfig)
```

### Node.js

```javascript
const AWS = require('aws-sdk');
const sm = new AWS.SecretsManager();

const secret = await sm.getSecretValue({
  SecretId: 'shared/platform/app/db'
}).promise();

const dbConfig = JSON.parse(secret.SecretString);
const db = createConnection(dbConfig);
```

## Multi-Region Replication

This example configures replication to `eu-central-1`. The secret container is automatically replicated:

```bash
# List replicas
aws secretsmanager describe-secret \
  --secret-id shared/platform/app/db \
  --query 'ReplicationStatus'
```

You inject the secret once in the primary region, and it automatically replicates to all configured regions.

## Cleanup

```bash
terraform destroy
```

This will delete the secret with a 7-day recovery window (configurable).

## Next Steps

- Add **KMS encryption** with custom key (`kms_key_id` variable)
- Add **resource policies** for cross-account access (`resource_policy` variable)
- Set up **automatic rotation** with Lambda (`enable_rotation = true`)
- Integrate with **CI/CD pipeline** for automated secret injection
````
