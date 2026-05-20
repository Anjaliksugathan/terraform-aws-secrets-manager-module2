output "secret_arn" {
  description = "ARN of the secret (for IAM policies, Lambda access)"
  value       = aws_secretsmanager_secret.this.arn
  sensitive   = false
}

output "secret_name" {
  description = "Name of the secret (for application lookups)"
  value       = aws_secretsmanager_secret.this.name
  sensitive   = false
}

output "secret_version_id" {
  description = "Current version ID of the secret (for debugging)"
  value       = aws_secretsmanager_secret_version.this.version_id
  sensitive   = true
}

output "source_type" {
  description = "Source of the injected secrets (vault, azure_keyvault, or direct)"
  value       = local.source_type
  sensitive   = false
}
