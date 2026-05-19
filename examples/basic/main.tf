provider "aws" {
  region = "eu-west-1"
}

module "app_secret" {
  source = "../../"

  name        = "shared/platform/app/db"
  description = "Application database credentials"

  secret_values = var.secret_values

  replica_regions = [
    "eu-central-1"
  ]

  recovery_window_in_days = 7

  tags = {
    Environment = "prod"
    Team        = "platform"
  }
}
