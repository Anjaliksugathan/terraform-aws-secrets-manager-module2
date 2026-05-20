locals {
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Module    = "terraform-aws-secrets-manager"
    }
  )
}

# ============================================================================
# SECURITY BEST PRACTICES - STATE FILE PROTECTION
# ============================================================================
#
# ⚠ CRITICAL: Even though secrets are pulled from external sources
# (Vault/Azure Key Vault), they WILL be stored in terraform.tfstate
#
# Mitigation strategies:
#
# 1. BACKEND ENCRYPTION
#    Configure S3 + KMS for state storage:
#    
#    terraform {
#      backend "s3" {
#        bucket            = "my-terraform-state"
#        key               = "secrets-manager/terraform.tfstate"
#        region            = "eu-west-1"
#        encrypt           = true
#        kms_key_id        = "arn:aws:kms:region:account:key/..."
#        dynamodb_table    = "terraform-locks"
#      }
#    }
#
# 2. IAM RESTRICTIONS
#    Limit who can read the state file:
#    - Only apply Terraform via CI/CD with restricted IAM role
#    - Never give users direct S3 access to state bucket
#    - Use bucket policies to deny all public access
#
# 3. SENSITIVE OUTPUTS
#    Don't output secrets in logs - only output metadata:
#    
#    output "secret_arn" {
#      value       = aws_secretsmanager_secret.this.arn
#      sensitive   = false  # Safe to log
#    }
#
# 4. LOCAL PRACTICES
#    - Add .terraform/ to .gitignore
#    - Use encrypted filesystem for terraform working directory
#    - Never commit terraform.tfvars to Git
#    - Use CI/CD secrets management, not local files
#
# See SECURITY.md for comprehensive security guidance
# ============================================================================
