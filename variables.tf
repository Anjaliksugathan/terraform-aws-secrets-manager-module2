variable "name" {
  description = "Name of the secret"
  type        = string

  validation {
    condition     = length(var.name) > 3
    error_message = "Secret name must be longer than 3 characters."
  }
}

variable "description" {
  description = "Description of the secret"
  type        = string
  default     = ""
}

variable "kms_key_id" {
  description = "Optional KMS key ID or ARN"
  type        = string
  default     = null
}

variable "secret_values" {
  description = "Secret key/value pairs (ignored if using Vault/KeyVault)"
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "secret_overrides" {
  description = "Additional secrets to merge with Vault/KeyVault secrets"
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "recovery_window_in_days" {
  description = "Recovery window before deletion"
  type        = number
  default     = 7

  validation {
    condition     = var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30
    error_message = "Recovery window must be between 7 and 30 days."
  }
}

variable "enable_rotation" {
  description = "Enable secret rotation"
  type        = bool
  default     = false
}

variable "rotation_lambda_arn" {
  description = "Lambda ARN for rotation"
  type        = string
  default     = null
}

variable "rotation_days" {
  description = "Rotation interval"
  type        = number
  default     = 30
}

variable "replica_regions" {
  description = "List of replica AWS regions"
  type        = list(string)
  default     = []
}

variable "resource_policy" {
  description = "Optional resource policy JSON"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Vault Integration Variables
# ============================================================================

variable "use_vault_source" {
  description = "Enable HashiCorp Vault as the secret source"
  type        = bool
  default     = false
}

variable "vault_addr" {
  description = "Vault server address (or use VAULT_ADDR environment variable)"
  type        = string
  default     = ""
  sensitive   = false
}

variable "vault_token" {
  description = "Vault authentication token (or use VAULT_TOKEN environment variable)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vault_secret_path" {
  description = "Path to the secret in Vault (e.g., 'secret/data/prod/postgres' for KV v2 or 'secret/prod/postgres' for KV v1)"
  type        = string
  default     = ""
}

variable "vault_kv_version" {
  description = "Vault KV engine version (1 or 2)"
  type        = number
  default     = 2

  validation {
    condition     = var.vault_kv_version == 1 || var.vault_kv_version == 2
    error_message = "vault_kv_version must be either 1 or 2."
  }
}

# ============================================================================
# Azure Key Vault Integration Variables
# ============================================================================

variable "use_azure_keyvault_source" {
  description = "Enable Azure Key Vault as the secret source"
  type        = bool
  default     = false
}

variable "azure_keyvault_id" {
  description = "Azure Key Vault resource ID"
  type        = string
  default     = ""
}

variable "azure_keyvault_secret_name" {
  description = "Name of the secret in Azure Key Vault"
  type        = string
  default     = ""
}
