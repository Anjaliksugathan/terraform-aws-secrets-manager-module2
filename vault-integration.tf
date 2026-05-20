# Vault and Azure Key Vault integration for secret retrieval
# This file handles fetching secrets from external sources

# Data source for HashiCorp Vault
data "vault_generic_secret" "vault_secret" {
  count = var.use_vault_source ? 1 : 0

  path = var.vault_secret_path
}

# Data source for Azure Key Vault
data "azurerm_key_vault_secret" "azure_secret" {
  count = var.use_azure_keyvault_source ? 1 : 0

  name             = var.azure_keyvault_secret_name
  key_vault_id     = var.azure_keyvault_id
}

# Local that determines which secret source to use and merges them
locals {
  # Determine the source type
  source_type = var.use_vault_source ? "vault" : (
    var.use_azure_keyvault_source ? "azure_keyvault" : "direct"
  )

  # Fetch secrets from the appropriate source
  vault_secrets = var.use_vault_source ? (
    var.vault_kv_version == 2 ?
    data.vault_generic_secret.vault_secret[0].data.data :
    data.vault_generic_secret.vault_secret[0].data
  ) : {}

  azure_secrets = var.use_azure_keyvault_source ? (
    jsondecode(data.azurerm_key_vault_secret.azure_secret[0].value)
  ) : {}

  # Merge all secrets: vault base + azure base + local overrides
  final_secrets = merge(
    local.vault_secrets,
    local.azure_secrets,
    var.secret_overrides,
    var.secret_values
  )
}
