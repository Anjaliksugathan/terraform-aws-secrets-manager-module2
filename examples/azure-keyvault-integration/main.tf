terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
}

# Reference the Azure Key Vault
data "azurerm_key_vault" "this" {
  name                = var.azure_keyvault_name
  resource_group_name = var.azure_resource_group_name
}

# Deploy the secret to AWS Secrets Manager
module "app_secret" {
  source = "../../"

  name        = var.secret_name
  description = "Application configuration stored in Azure Key Vault"

  # Enable Azure Key Vault integration
  use_azure_keyvault_source   = true
  azure_keyvault_id           = data.azurerm_key_vault.this.id
  azure_keyvault_secret_name  = var.azure_secret_name

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
    Source      = "azure-keyvault"
  }
}

output "secret_arn" {
  description = "ARN of the secret in AWS Secrets Manager"
  value       = module.app_secret.secret_arn
}

output "secret_name" {
  description = "Name of the secret"
  value       = module.app_secret.secret_name
}

output "source_type" {
  description = "Secret source type"
  value       = module.app_secret.source_type
}
