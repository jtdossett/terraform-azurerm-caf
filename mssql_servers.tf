
# MSSQL server pre-computed configurations for performance optimization
locals {
  mssql_server_configs = {
    for key, value in local.database.mssql_servers : key => {
      # Pre-resolve resource group
      resource_group = local.combined_objects_resource_groups[try(value.resource_group.lz_key, local.client_config.landingzone_key)][try(value.resource_group_key, value.resource_group.key)]
      resource_group_name = can(value.resource_group.name) || can(value.resource_group_name) ? try(value.resource_group.name, value.resource_group_name) : null
      location = try(local.global_settings.regions[value.region], null)
      
      # Pre-resolve Key Vault
      keyvault_id = can(value.administrator_login_password) ? value.administrator_login_password : local.combined_objects_keyvaults[try(value.keyvault.lz_key, local.client_config.landingzone_key)][try(value.keyvault.key, value.keyvault_key)].id
    }
  }
  
  # Batch auditing storage account lookups to reduce API calls
  mssql_auditing_storage_data = {
    for key, value in local.database.mssql_servers : key => {
      storage_account_key = value.extended_auditing_policy.storage_account.key
      name = module.storage_accounts[value.extended_auditing_policy.storage_account.key].name
      resource_group_name = module.storage_accounts[value.extended_auditing_policy.storage_account.key].resource_group_name
      primary_access_key = module.storage_accounts[value.extended_auditing_policy.storage_account.key].primary_access_key
      primary_blob_endpoint = module.storage_accounts[value.extended_auditing_policy.storage_account.key].primary_blob_endpoint
    }
    if try(value.extended_auditing_policy, null) != null
  }
}

output "mssql_servers" {
  value = module.mssql_servers

}

module "mssql_servers" {
  source     = "./modules/databases/mssql_server"
  depends_on = [module.keyvault_access_policies, module.keyvault_access_policies_azuread_apps]
  for_each   = local.database.mssql_servers

  global_settings   = local.global_settings
  client_config     = local.client_config
  settings          = each.value
  
  # Use cached objects
  storage_accounts  = module.storage_accounts
  azuread_groups    = local.combined_objects_azuread_groups
  vnets             = local.combined_objects_networking
  private_endpoints = try(each.value.private_endpoints, {})
  private_dns       = local.combined_objects_private_dns
  resource_groups   = local.combined_objects_resource_groups

  # Use pre-computed values to eliminate repeated complex lookups
  base_tags           = local.global_settings.inherit_tags
  resource_group      = local.mssql_server_configs[each.key].resource_group
  resource_group_name = local.mssql_server_configs[each.key].resource_group_name
  location            = local.mssql_server_configs[each.key].location
  keyvault_id         = local.mssql_server_configs[each.key].keyvault_id

  remote_objects = {
    keyvault_keys = local.combined_objects_keyvault_keys
  }
}

# Optimized extended auditing policy with batched storage account data
resource "azurerm_mssql_server_extended_auditing_policy" "mssql" {
  depends_on = [azurerm_role_assignment.for]
  for_each   = local.mssql_auditing_storage_data

  server_id                               = module.mssql_servers[each.key].id
  storage_endpoint                        = each.value.primary_blob_endpoint
  storage_account_access_key             = each.value.primary_access_key
  storage_account_access_key_is_secondary = false
  retention_in_days                      = try(local.database.mssql_servers[each.key].extended_auditing_policy.retention_in_days, 0)
}

  log_monitoring_enabled                  = try(each.value.extended_auditing_policy.log_monitoring_enabled, false)
  server_id                               = module.mssql_servers[each.key].id
  storage_endpoint                        = data.azurerm_storage_account.mssql_auditing[each.key].primary_blob_endpoint
  storage_account_access_key              = data.azurerm_storage_account.mssql_auditing[each.key].primary_access_key
  storage_account_access_key_is_secondary = false
  retention_in_days                       = try(each.value.extended_auditing_policy.retention_in_days, null)
}

module "mssql_failover_groups" {
  source   = "./modules/databases/mssql_server/failover_group"
  for_each = local.database.mssql_failover_groups

  global_settings     = local.global_settings
  client_config       = local.client_config
  settings            = each.value
  resource_group_name = can(each.value.resource_group.name) || can(each.value.resource_group_name) ? try(each.value.resource_group.name, each.value.resource_group_name) : local.combined_objects_resource_groups[try(each.value.resource_group.lz_key, local.client_config.landingzone_key)][try(each.value.resource_group_key, each.value.resource_group.key)].name
  primary_server_name = local.combined_objects_mssql_servers[try(each.value.primary_server.lz_key, local.client_config.landingzone_key)][each.value.primary_server.sql_server_key].name
  secondary_server_id = local.combined_objects_mssql_servers[try(each.value.secondary_server.lz_key, local.client_config.landingzone_key)][each.value.secondary_server.sql_server_key].id
  databases           = local.combined_objects_mssql_databases
}