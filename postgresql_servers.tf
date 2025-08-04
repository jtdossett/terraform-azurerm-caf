
# PostgreSQL server pre-computed configurations for performance optimization
locals {
  postgresql_server_configs = {
    for key, value in local.database.postgresql_servers : key => {
      # Pre-resolve resource group
      resource_group = local.combined_objects_resource_groups[try(value.resource_group.lz_key, local.client_config.landingzone_key)][try(value.resource_group_key, value.resource_group.key)]
      resource_group_name = can(value.resource_group.name) || can(value.resource_group_name) ? try(value.resource_group.name, value.resource_group_name) : null
      location = try(local.global_settings.regions[value.region], null)
      
      # Pre-resolve Key Vault
      keyvault_id = try(value.administrator_login_password, null) == null ? module.keyvaults[value.keyvault_key].id : null
      
      # Pre-resolve subnet with optimized fallback logic
      subnet_id = can(value.subnet_id) || can(value.vnet_key) == false ? try(value.subnet_id, null) : try(local.combined_objects_virtual_subnets[try(value.lz_key, local.client_config.landingzone_key)][value.subnet_key].id, local.combined_objects_networking[try(value.lz_key, local.client_config.landingzone_key)][value.vnet_key].subnets[value.subnet_key].id)
    }
  }
}

output "postgresql_servers" {
  value = module.postgresql_servers

}

module "postgresql_servers" {
  source     = "./modules/databases/postgresql_server"
  depends_on = [module.keyvault_access_policies, module.keyvault_access_policies_azuread_apps]
  for_each   = local.database.postgresql_servers

  global_settings     = local.global_settings
  client_config       = local.client_config
  settings            = each.value
  
  # Use pre-computed values to eliminate complex expressions
  keyvault_id         = local.postgresql_server_configs[each.key].keyvault_id
  subnet_id           = local.postgresql_server_configs[each.key].subnet_id
  
  # Use cached objects
  storage_accounts    = module.storage_accounts
  azuread_groups      = module.azuread_groups
  vnets               = local.combined_objects_networking
  private_endpoints   = try(each.value.private_endpoints, {})
  private_dns         = local.combined_objects_private_dns
  virtual_subnets     = local.combined_objects_virtual_subnets
  diagnostics         = local.combined_diagnostics
  diagnostic_profiles = try(each.value.diagnostic_profiles, {})

  # Use pre-computed resource group info
  base_tags           = local.global_settings.inherit_tags
  resource_group      = local.postgresql_server_configs[each.key].resource_group
  resource_group_name = local.postgresql_server_configs[each.key].resource_group_name
  location            = local.postgresql_server_configs[each.key].location
}