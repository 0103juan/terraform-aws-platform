output "analyst" {
  description = "What the environment exposes: cluster, database, cache, registry, service accounts and secrets."
  value = {
    cluster_name             = module.analyst.cluster_name
    database_connection_name = module.analyst.database_connection_name
    database_user            = module.analyst.database_user
    cache_url                = module.analyst.cache_url
    image_repository         = module.analyst.image_repository
    service_accounts         = module.analyst.service_accounts
    secrets                  = module.analyst.secrets
  }
}
