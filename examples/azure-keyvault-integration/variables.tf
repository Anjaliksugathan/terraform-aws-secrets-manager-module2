variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "secret_name" {
  description = "Name of the secret in AWS Secrets Manager"
  type        = string
  default     = "shared/platform/app/config"
}

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "azure_tenant_id" {
  description = "Azure tenant ID"
  type        = string
  sensitive   = true
}

variable "azure_client_id" {
  description = "Azure service principal client ID"
  type        = string
  sensitive   = true
}

variable "azure_client_secret" {
  description = "Azure service principal client secret"
  type        = string
  sensitive   = true
}

variable "azure_keyvault_name" {
  description = "Name of the Azure Key Vault"
  type        = string
}

variable "azure_resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "azure_secret_name" {
  description = "Name of the secret in Azure Key Vault"
  type        = string
}

variable "kms_key_id" {
  description = "Optional KMS key for secret encryption"
  type        = string
  default     = null
}

variable "enable_rotation" {
  description = "Enable automatic secret rotation"
  type        = bool
  default     = false
}

variable "rotation_lambda_arn" {
  description = "Lambda ARN for rotation (required if enable_rotation is true)"
  type        = string
  default     = null
}

variable "rotation_days" {
  description = "Rotation interval in days"
  type        = number
  default     = 30
}
