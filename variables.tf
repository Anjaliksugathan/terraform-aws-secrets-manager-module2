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
  description = "Secret key/value pairs"
  type        = map(string)
  sensitive   = true
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
