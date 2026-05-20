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
  description = "Name of the secret to manage"
  type        = string
  default     = "shared/platform/postgres/credentials"
}

variable "vault_addr" {
  description = "Vault server address"
  type        = string
}

variable "vault_token" {
  description = "Vault authentication token"
  type        = string
  sensitive   = true
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
