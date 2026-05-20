# Azure Key Vault Integration Example

This example demonstrates how to use the Terraform AWS Secrets Manager module with **Azure Key Vault** as the secret source.

## Prerequisites

1. **Azure subscription** with active access
2. **Azure Key Vault** created and accessible
3. **Service Principal** with permissions to read Key Vault secrets
4. **AWS credentials** configured (via AWS CLI, environment variables, or IAM role)
5. **Terraform** >= 1.0

## Setup

### Step 1: Create Azure Service Principal

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Create a service principal
az ad sp create-for-rbac --name "terraform-secrets" --role Reader

# Note the output:
# {
#   "appId": "your-client-id",
#   "displayName": "terraform-secrets",
#   "password": "your-client-secret",
#   "tenant": "your-tenant-id"
# }
```

### Step 2: Grant Key Vault Access

```bash
SP_OBJECT_ID=$(az ad sp list --display-name "terraform-secrets" --query '[0].id' -o tsv)

az keyvault set-policy \
  --name "your-keyvault-name" \
  --object-id "$SP_OBJECT_ID" \
  --secret-permissions get list
```

### Step 3: Store Secrets in Azure Key Vault

```bash
# Create a secret with database credentials (must be valid JSON)
az keyvault secret set \
  --vault-name "your-keyvault-name" \
  --name "app-credentials" \
  --value '{"username":"admin","password":"your-secure-password","host":"db.example.com"}'

# Verify the secret
az keyvault secret show --vault-name "your-keyvault-name" --name "app-credentials"
```

### Step 4: Create terraform.tfvars

```hcl
aws_region                  = "eu-west-1"
environment                 = "prod"
secret_name                 = "shared/platform/app/config"
az_subscription_id          = "your-subscription-id"
az_tenant_id                = "your-tenant-id"
az_client_id                = "your-client-id"
az_client_secret            = "your-client-secret"
azure_keyvault_name        = "your-keyvault-name"
azure_resource_group_name  = "your-resource-group"
azure_secret_name          = "app-credentials"
```

### Step 5: Deploy

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy (secrets are fetched from Azure Key Vault and injected into AWS Secrets Manager)
terraform apply
```

## How It Works

1. **Terraform authenticates** with Azure using the service principal
2. **Retrieves the secret** from Azure Key Vault
3. **Parses the secret** (must be valid JSON)
4. **Injects the secrets** into AWS Secrets Manager in a single API call
5. **Tags the secret** with `Source: azure_keyvault` for audit trail

## Advantages

✅ **Hybrid cloud setup** — Secrets in Azure, deployment in AWS
✅ **Centralized management** — Single source of truth for secrets
✅ **One-shot deployment** — Single `terraform apply` command
✅ **No manual secret passing** — Automated secret retrieval
✅ **Audit trail** — Every secret access logged in Azure
✅ **Multi-region support** — AWS Secrets Manager replication
✅ **KMS encryption** — Optional AWS KMS key for encryption

## Secret Format

Secrets in Azure Key Vault **must be valid JSON**:

```json
{
  "username": "admin",
  "password": "secure-password",
  "host": "db.example.com",
  "port": "5432",
  "database": "myapp"
}
```

This will be injected as-is into AWS Secrets Manager.

## Verifying the Deployment

```bash
# Check the secret in AWS Secrets Manager
aws secretsmanager describe-secret \
  --secret-id shared/platform/app/config \
  --region eu-west-1

# Retrieve the secret value
aws secretsmanager get-secret-value \
  --secret-id shared/platform/app/config \
  --region eu-west-1 | jq '.SecretString | fromjson'
```

## Troubleshooting

### "Error: Unauthorized to perform action"
- Verify service principal has Reader role
- Check Key Vault access policies: `az keyvault show-deleted --name "your-keyvault-name" --resource-group "your-rg"`

### "Secret not found in Key Vault"
- Verify secret name: `az keyvault secret list --vault-name "your-keyvault-name"`
- Check secret value is valid JSON: `az keyvault secret show --vault-name "your-keyvault-name" --name "app-credentials"`

### "Invalid JSON in secret"
- Ensure the secret value is valid JSON
- Use `jq` to validate: `echo 'your-secret-value' | jq .

### "Terraform state contains secrets"
- Use an encrypted remote state backend
- Apply `terraform state lock` with Azure Storage
- Restrict IAM access to the state bucket

## Security Best Practices

1. **Never commit credentials** — Use environment variables or Terraform Cloud
2. **Use managed identities** — If running from Azure VMs/Functions
3. **Rotate credentials** — Implement a regular rotation schedule
4. **Enable audit logging** — In Azure Key Vault and AWS CloudTrail
5. **Use encrypted state backend** — Azure Storage with encryption
6. **Restrict permissions** — Least privilege principle
7. **Enable MFA** — For Azure account access

## Cleanup

```bash
# Destroy AWS resources
terraform destroy

# Optionally delete the secret from Azure Key Vault
az keyvault secret delete --vault-name "your-keyvault-name" --name "app-credentials"
```

## Advanced: Multiple Secrets with Loop

```hcl
locals {
  secrets = {
    app = {
      name     = "shared/platform/app/config"
      azure_name = "app-credentials"
    }
    db = {
      name     = "shared/platform/db/config"
      azure_name = "db-credentials"
    }
  }
}

module "app_secrets" {
  for_each = local.secrets
  source   = "../../"

  name        = each.value.name
  description = "${each.key} configuration from Azure Key Vault"

  use_azure_keyvault_source   = true
  azure_keyvault_id           = data.azurerm_key_vault.this.id
  azure_keyvault_secret_name  = each.value.azure_name

  tags = {
    Environment = var.environment
    Component   = each.key
  }
}

output "secret_arns" {
  value = {
    for name, secret in module.app_secrets :
    name => secret.secret_arn
  }
}
```

## Next Steps

- Integrate with CI/CD pipeline (GitHub Actions, Azure DevOps, GitLab CI)
- Set up automatic secret rotation with Lambda
- Enable audit logging for compliance
- Implement cross-account access with resource policies
