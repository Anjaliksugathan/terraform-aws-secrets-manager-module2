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

variable "db_host" {
  description = "PostgreSQL database hostname"
  type        = string
}

variable "db_port" {
  description = "PostgreSQL database port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "postgres"
}

variable "db_username" {
  description = "Database username. Injected at runtime, never in Git."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Initial database password. Injected at runtime, never in Git."
  type        = string
  sensitive   = true
}

variable "kms_key_id" {
  description = "Optional KMS key for secret encryption"
  type        = string
  default     = null
}

# TODO: Add VPC configuration variables for private database access
# variable "lambda_subnet_ids" {
#   description = "Subnet IDs for Lambda VPC configuration"
#   type        = list(string)
#   default     = []
# }

# variable "lambda_security_group_id" {
#   description = "Security group for Lambda in VPC"
#   type        = string
#   default     = null
# }
