# Function app pre-computed configurations for performance optimization
locals {
  function_app_configs = {
    for key, value in local.webapp.function_apps : key => {
      # Pre-resolve storage account to avoid data source lookups
      storage_account = can(value.storage_account.key) ? {
        name       = local.combined_objects_storage_accounts[try(value.storage_account.lz_key, local.client_config.landingzone_key)][value.storage_account.key].name
        access_key = local.combined_objects_storage_accounts[try(value.storage_account.lz_key, local.client_config.landingzone_key)][value.storage_account.key].primary_access_key
      } : null
      
      # Pre-resolve resource group to avoid repeated complex lookups
      resource_group = local.combined_objects_resource_groups[try(value.resource_group.lz_key, local.client_config.landingzone_key)][try(value.resource_group_key, value.resource_group.key)]
      resource_group_name = can(value.resource_group.name) || can(value.resource_group_name) ? try(value.resource_group.name, value.resource_group_name) : null
      location = try(local.global_settings.regions[value.region], null)
    }
  }
}

module "function_apps" {
  source     = "./modules/webapps/function_app"
  depends_on = [module.networking]
  for_each   = local.webapp.function_apps

  name                       = each.value.name
  client_config              = local.client_config
  dynamic_app_settings       = try(each.value.dynamic_app_settings, {})
  app_settings               = try(each.value.app_settings, null)
  combined_objects           = local.dynamic_app_settings_combined_objects
  app_service_plan_id        = can(each.value.app_service_plan_id) || can(each.value.app_service_plan_key) == false ? try(each.value.app_service_plan_id, null) : local.combined_objects_app_service_plans[try(each.value.lz_key, local.client_config.landingzone_key)][each.value.app_service_plan_key].id
  settings                   = each.value.settings
  application_insight        = try(each.value.application_insight_key, null) == null ? null : module.azurerm_application_insights[each.value.application_insight_key]
  diagnostic_profiles        = try(each.value.diagnostic_profiles, null)
  diagnostics                = local.combined_diagnostics
  identity                   = try(each.value.identity, null)
  connection_strings         = try(each.value.connection_strings, {})
  
  # Use pre-computed storage account info (eliminates data source API calls)
  storage_account_name       = local.function_app_configs[each.key].storage_account != null ? local.function_app_configs[each.key].storage_account.name : null
  storage_account_access_key = local.function_app_configs[each.key].storage_account != null ? local.function_app_configs[each.key].storage_account.access_key : null
  
  tags                       = try(each.value.tags, null)
  global_settings   = local.global_settings
  private_dns       = local.combined_objects_private_dns
  private_endpoints = try(each.value.private_endpoints, {})
  vnets             = local.combined_objects_networking
  virtual_subnets   = local.combined_objects_virtual_subnets
  remote_objects = {
    subnets = try(local.combined_objects_networking[try(each.value.settings.lz_key, local.client_config.landingzone_key)][each.value.settings.vnet_key].subnets, null)
  }

  # Use pre-computed resource group info (eliminates complex try() expressions)
  base_tags           = local.global_settings.inherit_tags
  resource_group      = local.function_app_configs[each.key].resource_group
  resource_group_name = local.function_app_configs[each.key].resource_group_name
  location            = local.function_app_configs[each.key].location
}

output "function_apps" {
  value = module.function_apps
}
