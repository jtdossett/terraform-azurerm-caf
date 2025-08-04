
# Storage account pre-computed configurations for performance optimization
locals {
  storage_account_configs = {
    for key, value in var.storage_accounts : key => {
      # Pre-resolve resource group to avoid repeated complex lookups
      resource_group = local.combined_objects_resource_groups[try(value.resource_group.lz_key, local.client_config.landingzone_key)][try(value.resource_group_key, value.resource_group.key)]
      resource_group_name = can(value.resource_group.name) || can(value.resource_group_name) ? try(value.resource_group.name, value.resource_group_name) : null
      location = try(local.global_settings.regions[value.region], null)
      
      # Pre-resolve diagnostic profiles to reduce try() calls
      diagnostic_profiles = try(value.diagnostic_profiles, {})
      diagnostic_profiles_blob = try(value.diagnostic_profiles_blob, {})
      diagnostic_profiles_queue = try(value.diagnostic_profiles_queue, {})
      diagnostic_profiles_table = try(value.diagnostic_profiles_table, {})
      diagnostic_profiles_file = try(value.diagnostic_profiles_file, {})
      
      # Pre-resolve customer managed key configuration
      cmk_config = can(value.customer_managed_key) ? {
        keyvault_id = local.combined_objects_keyvaults[try(value.customer_managed_key.lz_key, local.client_config.landingzone_key)][value.customer_managed_key.keyvault_key].id
        key_name = can(value.customer_managed_key.key_name) ? value.customer_managed_key.key_name : local.combined_objects_keyvault_keys[try(value.customer_managed_key.lz_key, local.client_config.landingzone_key)][value.customer_managed_key.keyvault_key_key].name
        key_version = try(value.customer_managed_key.key_version, null)
      } : null
    }
  }
}

module "storage_accounts" {
  source   = "./modules/storage_account"
  for_each = var.storage_accounts

  client_config       = local.client_config
  storage_account     = each.value
  var_folder_path     = var.var_folder_path
  
  # Use pre-computed diagnostic profiles (reduces 5 try() calls to 0)
  diagnostic_profiles       = local.storage_account_configs[each.key].diagnostic_profiles
  diagnostic_profiles_blob  = local.storage_account_configs[each.key].diagnostic_profiles_blob
  diagnostic_profiles_queue = local.storage_account_configs[each.key].diagnostic_profiles_queue
  diagnostic_profiles_table = local.storage_account_configs[each.key].diagnostic_profiles_table
  diagnostic_profiles_file  = local.storage_account_configs[each.key].diagnostic_profiles_file
  
  # Use cached combined objects
  diagnostics        = local.combined_diagnostics
  global_settings    = local.global_settings
  managed_identities = local.combined_objects_managed_identities
  private_dns        = local.combined_objects_private_dns
  recovery_vaults    = local.combined_objects_recovery_vaults
  vnets              = local.combined_objects_networking
  virtual_subnets    = local.combined_objects_virtual_subnets
  
  private_endpoints = try(each.value.private_endpoints, {})
  
  # Use pre-computed resource group info (eliminates complex try() expressions)
  base_tags           = local.global_settings.inherit_tags
  resource_group      = local.storage_account_configs[each.key].resource_group
  resource_group_name = local.storage_account_configs[each.key].resource_group_name
  location            = local.storage_account_configs[each.key].location
}

output "storage_accounts" {
  value     = module.storage_accounts
  sensitive = true
}

resource "azurerm_storage_account_customer_managed_key" "cmk" {
  depends_on = [module.keyvault_access_policies]
  for_each = {
    for key, config in local.storage_account_configs : key => config
    if config.cmk_config != null
  }

  storage_account_id = module.storage_accounts[each.key].id
  key_vault_id       = each.value.cmk_config.keyvault_id
  key_name           = each.value.cmk_config.key_name
  key_version        = each.value.cmk_config.key_version
}

module "encryption_scopes" {
  source = "./modules/storage_account/encryption_scope"
  for_each = {
    for key, value in var.storage_accounts : key => value
    if can(value.encryption_scopes)
  }

  client_config      = local.client_config
  settings           = each.value
  storage_account_id = module.storage_accounts[each.key].id
  keyvault_keys      = local.combined_objects_keyvault_keys
}
