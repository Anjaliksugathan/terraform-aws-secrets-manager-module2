# Reference implementation: AWS Secrets Manager rotation for PostgreSQL
# 
# This example shows how infra teams integrate the secrets module with
# a rotation Lambda function.
#
# Usage:
#   terraform -chdir=examples/rotation_lambda apply -var-file=terraform.tfvars

provider "aws" {
  region = var.aws_region
}

# ============================================================================
# 1. IAM Role for Lambda (Least Privilege)
# ============================================================================

resource "aws_iam_role" "rotation_lambda" {
  name = "secrets-manager-rotation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Allow Lambda to read/write secrets versions
resource "aws_iam_role_policy" "rotation_lambda_secrets" {
  name = "rotation-lambda-secrets-policy"
  role = aws_iam_role.rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.example.arn
      }
    ]
  })
}

# Allow Lambda to write logs
resource "aws_iam_role_policy_attachment" "rotation_lambda_logs" {
  role       = aws_iam_role.rotation_lambda.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# TODO: Add VPC policy if Lambda needs to access database in private subnets
# resource "aws_iam_role_policy" "rotation_lambda_vpc" {
#   ...
# }

# ============================================================================
# 2. CloudWatch Log Group for Lambda
# ============================================================================

resource "aws_cloudwatch_log_group" "rotation_lambda" {
  name              = "/aws/lambda/secrets-rotation"
  retention_in_days = 7  # TODO: Adjust based on compliance requirements

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "Secrets Manager Rotation"
  }
}

# ============================================================================
# 3. Lambda Function (Rotation Handler)
# ============================================================================

# Package Lambda code (assumes lambda_handler.py exists in this directory)
data "archive_file" "rotation_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_handler.py"
  output_path = "${path.module}/lambda_handler.zip"

  # Simpler approach than Lambda layers for this example
  # TODO: For production, add dependencies (psycopg2) via:
  # - Lambda layer with compiled packages
  # - Container image with dependencies pre-installed
  # - Pre-built zip with vendor/ directory
}

resource "aws_lambda_function" "rotation" {
  filename         = data.archive_file.rotation_lambda.output_path
  function_name    = "secrets-manager-rotation"
  role             = aws_iam_role.rotation_lambda.arn
  handler          = "lambda_handler.lambda_handler"
  source_code_hash = data.archive_file.rotation_lambda.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60

  # Database connection parameters (from environment)
  environment {
    variables = {
      DB_HOST = var.db_host
      DB_PORT = var.db_port
      DB_NAME = var.db_name
    }
  }

  # TODO: Add VPC config if database is in private subnet:
  # vpc_config {
  #   subnet_ids         = var.lambda_subnet_ids
  #   security_group_ids = [aws_security_group.lambda.id]
  # }

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "Secrets Manager Rotation"
  }
}

# Allow Secrets Manager to invoke the Lambda
resource "aws_lambda_permission" "rotation" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
}

# ============================================================================
# 4. Secret (using the module from repo root)
# ============================================================================

module "db_secret" {
  source = "../../"

  name        = var.secret_name
  description = "PostgreSQL database credentials with automatic rotation"

  secret_values = {
    username = var.db_username
    password = var.db_password
  }

  # Enable rotation
  enable_rotation     = true
  rotation_lambda_arn = aws_lambda_function.rotation.arn
  rotation_days       = 30  # Rotate every 30 days

  # Optional: KMS encryption
  kms_key_id = var.kms_key_id

  tags = {
    Environment = var.environment
    Team        = "infra"
    Application = "shared-platform"
  }

  # Ensure Lambda is configured before enabling rotation
  depends_on = [
    aws_lambda_function.rotation,
    aws_lambda_permission.rotation
  ]
}

# ============================================================================
# 5. Outputs
# ============================================================================

output "secret_arn" {
  description = "ARN of the rotated secret"
  value       = module.db_secret.secret_arn
}

output "secret_name" {
  description = "Name of the rotated secret"
  value       = module.db_secret.secret_name
}

output "rotation_lambda_arn" {
  description = "ARN of the rotation Lambda function"
  value       = aws_lambda_function.rotation.arn
}

# TODO (Production Improvements):
# - Add CloudWatch alarms for rotation failures
# - Add SNS topic for rotation notifications
# - Add metrics for rotation latency / success rate
# - Add cross-account secret access patterns
# - Add backup/recovery procedures for rotation failures
# - Add certificate rotation support (not just passwords)
# - Document runbook for manual rotation if Lambda fails
# - Test rotation in staging before production deployment
