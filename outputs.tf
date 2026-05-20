output "secret_arn" {
  description = "ARN of the secret (for IAM policies, Lambda access, applications)"
  value       = aws_secretsmanager_secret.this.arn
}

output "secret_name" {
  description = "Name of the secret (for application lookups and AWS CLI)"
  value       = aws_secretsmanager_secret.this.name
}

output "secret_id" {
  description = "ID of the secret (same as name, use for AWS API calls)"
  value       = aws_secretsmanager_secret.this.id
}

output "kms_key_id" {
  description = "KMS key ID used for encryption"
  value       = aws_secretsmanager_secret.this.kms_key_id
}

output "replica_regions" {
  description = "List of regions where secret is replicated"
  value       = var.replica_regions
}
