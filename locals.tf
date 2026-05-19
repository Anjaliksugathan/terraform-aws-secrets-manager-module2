locals {
  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Module    = "terraform-aws-secrets-manager"
    }
  )
}
