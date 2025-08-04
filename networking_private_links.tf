# Private endpoints pre-computed configurations for performance optimization
locals {
  private_endpoint_configs = {
    for key, value in try(var.networking.private_endpoints, {}) : key => {
      # Pre-resolve VNet information
      vnet = try(local.combined_objects_networking[value.lz_key][value.vnet_key], local.combined_objects_networking[local.client_config.landingzone_key][value.vnet_key])
      
      # Optimize remote_objects - only include what's needed for this endpoint type
      optimized_remote_objects = {
        # Diagnostic resources (common to all)
        diagnostic_storage_accounts     = local.combined_diagnostics.storage_accounts
        diagnostic_event_hub_namespaces = local.combined_diagnostics.event_hub_namespaces
        
        # Only include objects relevant to this specific endpoint
        aks_clusters                = can(value.resource.aks_cluster_key) ? local.combined_objects_aks_clusters : {}
        app_config                  = can(value.resource.app_config_key) ? local.combined_objects_app_config : {}
        batch_accounts              = can(value.resource.batch_account_key) ? local.combined_objects_batch_accounts : {}
        azure_container_registries  = can(value.resource.container_registry_key) ? local.combined_objects_azure_container_registries : {}
        cognitive_services_accounts = can(value.resource.cognitive_service_key) ? local.combined_objects_cognitive_services_accounts : {}
        cosmos_dbs                  = can(value.resource.cosmos_db_key) ? local.combined_objects_cosmos_dbs : {}
        data_factory                = can(value.resource.data_factory_key) ? local.combined_objects_data_factory : {}
        event_hub_namespaces        = can(value.resource.event_hub_namespace_key) ? local.combined_objects_event_hub_namespaces : {}
        keyvaults                   = can(value.resource.keyvault_key) ? local.combined_objects_keyvaults : {}
        machine_learning            = can(value.resource.machine_learning_key) ? local.combined_objects_machine_learning : {}
        mssql_servers               = can(value.resource.mssql_server_key) ? local.combined_objects_mssql_servers : {}
        mysql_servers               = can(value.resource.mysql_server_key) ? local.combined_objects_mysql_servers : {}
        postgresql_servers          = can(value.resource.postgresql_server_key) ? local.combined_objects_postgresql_servers : {}
        recovery_vaults             = can(value.resource.recovery_vault_key) ? local.combined_objects_recovery_vaults : {}
        redis_caches                = can(value.resource.redis_cache_key) ? local.combined_objects_redis_caches : {}
        storage_accounts            = can(value.resource.storage_account_key) ? local.combined_objects_storage_accounts : {}
        synapse_workspaces          = can(value.resource.synapse_workspace_key) ? local.combined_objects_synapse_workspaces : {}
        signalr_services            = can(value.resource.signalr_service_key) ? local.combined_objects_signalr_services : {}
        
        # Networking (common to all)
        networking                  = local.combined_objects_networking
      }
    }
  }
}

module "private_endpoints" {
  source   = "./modules/networking/private_links/endpoints"
  for_each = try(var.networking.private_endpoints, {})

  global_settings   = local.global_settings
  client_config     = local.client_config
  resource_groups   = local.combined_objects_resource_groups
  settings          = each.value
  private_endpoints = var.networking.private_endpoints
  private_dns       = local.combined_objects_private_dns
  base_tags         = local.global_settings.inherit_tags
  
  # Use pre-computed VNet
  vnet              = local.private_endpoint_configs[each.key].vnet
  
  # Use optimized remote_objects - significantly reduced size per endpoint
  remote_objects    = local.private_endpoint_configs[each.key].optimized_remote_objects
}

output "private_endpoints" {
  value = module.private_endpoints
}
