terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}

module "postgres_secret" {
  source = "../../"

  name        = var.secret_name
  description = "PostgreSQL database credentials managed via Vault"

  # Enable Vault integration
  use_vault_source  = true
  vault_addr        = var.vault_addr
  vault_token       = var.vault_token
  vault_secret_path = "secret/data/${var.environment}/postgres"
  vault_kv_version  = 2

  # Multi-region replication
  replica_regions = [
    "eu-central-1",
    "eu-west-2"
  ]

  # KMS encryption
  kms_key_id = var.kms_key_id

  # Recovery window
  recovery_window_in_days = 7

  # Optional: Enable rotation
  enable_rotation     = var.enable_rotation
  rotation_lambda_arn = var.rotation_lambda_arn
  rotation_days       = var.rotation_days

  tags = {
    Environment = var.environment
    Team        = "platform"
    Source      = "vault"
  }
}

# Output the secret ARN for reference
output "secret_arn" {
  description = "ARN of the secret in AWS Secrets Manager"
  value       = module.postgres_secret.secret_arn
}

output "secret_name" {
  description = "Name of the secret"
  value       = module.postgres_secret.secret_name
}

output "source_type" {
  description = "Secret source type"
  value       = module.postgres_secret.source_type
}
