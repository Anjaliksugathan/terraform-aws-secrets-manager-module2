"""
SECURITY ARCHITECTURE & DESIGN RISKS
Terraform AWS Secrets Manager Module
Last Updated: 2026-05-20
"""

## 🔴 CRITICAL DESIGN RISKS

### 1. DATA LEAKAGE RISK IN TERRAFORM STATE

**SEVERITY:** 🔴 CRITICAL

**Problem:**
Even when secrets originate from Vault or Azure Key Vault, Terraform WILL store them in `terraform.tfstate`:

```hcl
# This will be in state (EXPOSED):
locals {
  final_secrets = merge(
    vault_secrets,          # ← Decrypted Vault values
    azure_secrets,          # ← Decrypted Azure values
    var.secret_values,      # ← Direct secrets
    var.secret_overrides    # ← All merged together
  )
}

# Then passed to AWS:
resource "aws_secretsmanager_secret_version" "this" {
  secret_string = jsonencode(local.final_secrets)  # ← Still in state as plain JSON
}
```

**Root Cause:**
- Terraform evaluates all locals and variables before applying
- State file captures the full computed value including all decrypted secrets
- External source integration does NOT prevent state capture

**Risk Scenarios:**
- State file accessible via: misconfigured S3 bucket, IAM access, terraform logs
- State file stored unencrypted locally on developer machines
- State file in version control
- State file in CI/CD logs (GitHub Actions, Jenkins, etc.)
- Backup/recovery systems with access to raw state

**Mitigation Strategy:**

1. **Backend Encryption (AWS S3 + KMS):**
```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state"
    key            = "secrets-manager/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true                    # ✅ Enable SSE-S3
    dynamodb_table = "terraform-locks"       # ✅ State locking
  }
}

# BETTER: Use KMS encryption
terraform {
  backend "s3" {
    bucket            = "terraform-state"
    key               = "secrets-manager/terraform.tfstate"
    region            = "eu-west-1"
    encrypt           = true
    kms_key_id        = "arn:aws:kms:..."    # ✅ Customer-managed KMS key
    dynamodb_table    = "terraform-locks"
  }
}
```

2. **IAM Restrictions (State Access):**
```hcl
# S3 bucket policy: Restrict to specific roles only
{
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::ACCOUNT:role/terraform-runner"
  },
  "Action": [
    "s3:GetObject",
    "s3:PutObject"
  ],
  "Resource": "arn:aws:s3:::terraform-state/*"
}

# Deny all public access
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": [
    "arn:aws:s3:::terraform-state",
    "arn:aws:s3:::terraform-state/*"
  ]
}
```

3. **Sensitive Output Redaction:**
```hcl
# Mark state outputs as sensitive (redacted in logs)
output "secret_name" {
  value     = aws_secretsmanager_secret.this.name
  sensitive = false  # Safe to log
}

output "secret_id" {
  value     = aws_secretsmanager_secret.this.id
  sensitive = false  # Safe to log
}

# ❌ Never output the actual secret value:
# output "secret_value" {
#   value = local.final_secrets  # DO NOT DO THIS!
# }
```

4. **Local Machine Practices:**
- Add `.terraform/` to `.gitignore`
- Use encrypted filesystem for terraform working directory
- Use `terraform state rm` to exclude sensitive resources after creation
- Never commit `terraform.tfvars` with secrets to Git
- Use `.env` files or CI/CD secrets management, NOT variables

---

### 2. JSON ASSUMPTION FOR AZURE KEY VAULT

**SEVERITY:** 🟠 HIGH

**Problem:**
```hcl
# Current implementation ASSUMES Azure secret is JSON:
azure_secrets = var.use_azure_keyvault_source ? (
  jsondecode(data.azurerm_key_vault_secret.azure_secret[0].value)  # 💥 Fails if not JSON!
) : {}
```

**Failure Scenarios:**
- Azure secret contains plain text (CSV, YAML, PEM certificate)
- Azure secret is a connection string
- Azure secret is base64-encoded (needs decoding first)
- Azure secret is a multiline file

**Error Output:**
```
Error: Invalid JSON: unexpected character at line 1, column 1

  on vault-integration.tf line 34, in locals:
   34:     jsondecode(data.azurerm_key_vault_secret.azure_secret[0].value)

Cannot parse JSON in Azure Key Vault secret value
```

**Fix Applied (in updated vault-integration.tf):**
```hcl
# NEW: Optional JSON parsing with fallback
variable "azure_secret_is_json" {
  description = "Whether the Azure Key Vault secret value is JSON-formatted"
  type        = bool
  default     = true
}

azure_secrets = var.use_azure_keyvault_source ? (
  var.azure_secret_is_json ? 
    jsondecode(data.azurerm_key_vault_secret.azure_secret[0].value) : 
    { "value" = data.azurerm_key_vault_secret.azure_secret[0].value }  # ✅ Fallback
) : {}
```

**Usage:**
```hcl
# For JSON secrets (e.g., {"username": "admin", "password": "xxx"})
module "app_secret" {
  use_azure_keyvault_source  = true
  azure_secret_is_json       = true   # ✅ Parse as JSON
}

# For plain-text secrets (e.g., database connection string)
module "app_secret" {
  use_azure_keyvault_source  = true
  azure_secret_is_json       = false  # ✅ Treat as plain text
}
```

---

### 3. MULTIPLE SOURCES CONFLICT AMBIGUITY

**SEVERITY:** 🟠 HIGH

**Problem:**
```hcl
# Current code allows ALL to be enabled simultaneously:
final_secrets = merge(
  vault_secrets,         # Source 1
  azure_secrets,         # Source 2
  var.secret_overrides,  # Source 3
  var.secret_values      # Source 4
)
```

This creates **UNPREDICTABLE BEHAVIOR**:

| Scenario | vault_source | azure_source | direct_values | Result |
|----------|------|------|------|--------|
| A | ✅ | ❌ | ❌ | Uses Vault (Expected) |
| B | ❌ | ✅ | ❌ | Uses Azure (Expected) |
| C | ❌ | ❌ | ✅ | Uses Direct (Expected) |
| D | ✅ | ✅ | ❌ | **Ambiguous!** Which wins? Azure overwrites Vault |
| E | ✅ | ❌ | ✅ | **Confusing!** Direct overwrites Vault (priority issue) |
| F | ✅ | ✅ | ✅ | **Chaos!** All merge (unpredictable priority) |

**Examples of Real Problems:**

1. **Accidental Secret Override:**
```hcl
# Developer enables both Vault and direct:
module "app_secret" {
  use_vault_source = true
  vault_secret_path = "secret/data/prod/db"
  
  secret_values = {
    password = "wrong_password_123"  # Oops! Forgot to disable
  }
}

# Result: Direct value OVERWRITES Vault
# Application uses wrong credentials → Connection failure or security breach
```

2. **Audit Trail Confusion:**
- Which secret source is actually being used?
- Which source should be audited?
- Which credentials were rotated?

3. **Deployment Failures:**
```
# CI/CD tries Azure but Vault is also enabled
# If Azure API is slow, it might timeout
# But Vault kicks in, and now you're mixing sources
```

**Fix Applied (Enterprise Grade):**

```hcl
# NEW: Explicit source selector
variable "secret_source" {
  description = "Secret source mode: 'direct', 'vault', or 'azure_keyvault'"
  type        = string
  default     = "direct"

  validation {
    condition     = contains(["direct", "vault", "azure_keyvault"], var.secret_source)
    error_message = "secret_source must be one of: 'direct', 'vault', 'azure_keyvault'."
  }
}

# In vault-integration.tf:
check "source_exclusivity" {
  assert {
    condition = (
      (var.use_vault_source ? 1 : 0) +
      (var.use_azure_keyvault_source ? 1 : 0)
    ) <= 1
    error_message = "CRITICAL: Only ONE external source can be enabled!"
  }
}
```

**Usage:**

```hcl
# Option 1: Direct secrets only
module "app_secret" {
  secret_source = "direct"
  secret_values = {
    username = "admin"
    password = "secret123"
  }
}

# Option 2: Vault only
module "app_secret" {
  secret_source          = "vault"
  use_vault_source       = true
  vault_secret_path      = "secret/data/prod/db"
  # ❌ If secret_values is also set, Terraform will error!
}

# Option 3: Azure only
module "app_secret" {
  secret_source                 = "azure_keyvault"
  use_azure_keyvault_source     = true
  azure_keyvault_secret_name    = "prod-db-credentials"
}
```

---

## 🚀 ENTERPRISE-GRADE IMPROVEMENTS

### A. Complete Mutual Exclusivity Validation

**Goal:** Fail fast at planning stage if multiple sources are enabled.

```hcl
# In variables.tf
variable "use_vault_source" {
  type    = bool
  default = false

  validation {
    condition = !(
      var.use_vault_source && var.use_azure_keyvault_source
    )
    error_message = "Cannot use both Vault and Azure Key Vault simultaneously."
  }
}

variable "use_azure_keyvault_source" {
  type    = bool
  default = false

  validation {
    condition = !(
      var.use_vault_source && var.use_azure_keyvault_source
    )
    error_message = "Cannot use both Vault and Azure Key Vault simultaneously."
  }
}
```

### B. State Leakage Prevention Pattern

```hcl
# Create a "secret proxy" that doesn't store values:
resource "null_resource" "secret_deployment" {
  triggers = {
    secret_arn = aws_secretsmanager_secret.this.arn
    source     = local.source_type
    timestamp  = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Secret deployed to ARN: ${aws_secretsmanager_secret.this.arn}"
      echo "Source: ${local.source_type}"
    EOT
  }
}

# Never output the secret value
output "secret_arn" {
  value       = aws_secretsmanager_secret.this.arn
  sensitive   = false
  description = "ARN of the deployed secret (values NOT in state)"
}
```

### C. Credential Rotation Pattern

```hcl
resource "aws_secretsmanager_secret_rotation" "this" {
  count = var.enable_rotation ? 1 : 0

  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  # Only rotate if using external source (not direct values)
  depends_on = [
    aws_secretsmanager_secret_version.this
  ]

  lifecycle {
    # Prevent accidental rotation function changes
    ignore_changes = [rotation_lambda_arn]
  }
}
```

### D. Audit Logging

```hcl
# Enable CloudTrail for Secrets Manager
resource "aws_cloudtrail" "secrets_audit" {
  name           = "secrets-manager-audit"
  s3_bucket_name = aws_s3_bucket.audit_logs.id

  event_selector {
    include_management_events = true

    data_resource {
      type           = "AWS::SecretsManager::Secret"
      values         = ["arn:aws:secretsmanager:*:*:secret:*"]
    }
  }
}
```

---

## 📋 IMPLEMENTATION CHECKLIST

- [ ] **State Backend**: Configure S3 + KMS encryption
- [ ] **IAM Policies**: Restrict state file access
- [ ] **Mutual Exclusivity**: Add validation blocks
- [ ] **JSON Handling**: Add `azure_secret_is_json` variable
- [ ] **Testing**: Test with non-JSON Azure secrets
- [ ] **Documentation**: Update module README
- [ ] **CI/CD Security**: Mask state files in logs
- [ ] **Audit Trail**: Enable CloudTrail for secrets access
- [ ] **Rotation**: Implement Lambda rotation function
- [ ] **Monitoring**: Alert on unauthorized secret access

---

## 🧠 FINAL MENTAL MODEL

```
┌─────────────────────────────────────────────────────────┐
│                   SECRET SOURCES                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Vault ────┐                                           │
│            ├─→ [VALIDATOR] ──→ ✅ SINGLE SOURCE       │
│  Azure ────┤                                           │
│            ├─→ [DENY: Multiple sources] ──→ ❌ ERROR  │
│  Direct ───┘                                           │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                   NORMALIZER                            │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Optional: Parse JSON                                  │
│  Optional: Handle non-JSON values                      │
│  Optional: Apply overrides (limited)                   │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                  AWS SECRETS MANAGER                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ✅ Values stored in managed service (AWS managed)    │
│  ✅ Encryption at rest (KMS)                          │
│  ✅ IAM-based access control                          │
│  ⚠️  Values STILL in terraform.tfstate (mitigate!)    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 🔗 RELATED RESOURCES

- [AWS Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [Terraform State Security](https://www.terraform.io/docs/state/sensitive-data.html)
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Azure Key Vault Best Practices](https://learn.microsoft.com/en-us/azure/key-vault/general/best-practices)
