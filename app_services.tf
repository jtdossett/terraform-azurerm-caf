# Tested with :  AzureRM version 2.55.0
# Ref : https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/

# App service pre-computed configurations for performance optimization
locals {
  app_service_configs = {
    for key, value in local.webapp.app_services : key => {
      # Pre-resolve app service plan to avoid repeated lookups
      app_service_plan_id = can(value.app_service_plan_id) ? value.app_service_plan_id : local.combined_objects_app_service_plans[try(value.lz_key, local.client_config.landingzone_key)][value.app_service_plan_key].id
      
      # Pre-resolve subnet information
      subnet_id = can(value.subnet_id) || can(value.vnet_key) == false ? try(value.subnet_id, null) : local.combined_objects_networking[try(value.lz_key, local.client_config.landingzone_key)][value.vnet_key].subnets[value.subnet_key].id
      
      # Pre-resolve resource group
      resource_group = local.combined_objects_resource_groups[try(value.resource_group.lz_key, local.client_config.landingzone_key)][try(value.resource_group_key, value.resource_group.key)]
      resource_group_name = can(value.resource_group.name) || can(value.resource_group_name) ? try(value.resource_group.name, value.resource_group_name) : null
      location = try(local.global_settings.regions[value.region], null)
      
      # Pre-resolve application insights
      application_insight = try(value.application_insight_key, null) == null ? null : module.azurerm_application_insights[value.application_insight_key]
      
      # VNet integration config for batch processing
      vnet_integration = can(value.vnet_integration) ? {
        subnet_id = local.combined_objects_networking[try(value.vnet_integration.lz_key, local.client_config.landingzone_key)][value.vnet_integration.vnet_key].subnets[value.vnet_integration.subnet_key].id
      } : null
    }
  }
}

module "app_services" {
  source     = "./modules/webapps/appservice"
  depends_on = [module.networking]
  for_each   = local.webapp.app_services

  name               = each.value.name
  client_config      = local.client_config
  settings           = each.value.settings
  identity           = try(each.value.identity, null)
  connection_strings = try(each.value.connection_strings, {})
  app_settings       = try(each.value.app_settings, null)
  slots              = try(each.value.slots, {})
  global_settings    = local.global_settings
  
  # Use pre-computed values to eliminate repeated lookups
  app_service_plan_id                 = local.app_service_configs[each.key].app_service_plan_id
  subnet_id                           = local.app_service_configs[each.key].subnet_id
  application_insight                 = local.app_service_configs[each.key].application_insight
  
  # Use cached combined objects
  dynamic_app_settings                = try(each.value.dynamic_app_settings, {})
  combined_objects                    = local.dynamic_app_settings_combined_objects
  diagnostic_profiles                 = try(each.value.diagnostic_profiles, null)
  diagnostics                         = local.combined_diagnostics
  storage_accounts                    = local.combined_objects_storage_accounts
  private_endpoints                   = try(each.value.private_endpoints, {})
  vnets                               = local.combined_objects_networking
  private_dns                         = local.combined_objects_private_dns
  azuread_applications                = local.combined_objects_azuread_applications
  azuread_service_principal_passwords = local.combined_objects_azuread_service_principal_passwords

  # Use pre-computed resource group info
  base_tags           = local.global_settings.inherit_tags
  resource_group      = local.app_service_configs[each.key].resource_group
  resource_group_name = local.app_service_configs[each.key].resource_group_name
  location            = local.app_service_configs[each.key].location
}

output "app_services" {
  value = module.app_services
}

# Optimized VNet integration with batch processing
resource "azurerm_app_service_virtual_network_swift_connection" "vnet_config" {
  for_each = {
    for key, config in local.app_service_configs : key => config
    if config.vnet_integration != null
  }

  app_service_id = module.app_services[each.key].id
  subnet_id      = each.value.vnet_integration.subnet_id
}
