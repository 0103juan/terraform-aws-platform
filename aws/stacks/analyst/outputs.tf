output "cluster_name" {
  description = "Name of the EKS cluster: aws eks update-kubeconfig --name <this>."
  value       = module.eks.cluster_name
}

output "database_endpoint" {
  description = "Host name of the PostgreSQL instance."
  value       = module.postgres.endpoint
}

output "database_secret_arn" {
  description = "Secret that holds the database's master password."
  value       = module.postgres.master_secret_arn
}

output "model_api_key_secret_arn" {
  description = "Secret to put the model provider's API key in."
  value       = aws_secretsmanager_secret.model_api_key.arn
}

output "cache_url" {
  description = "Connection URL of the cache."
  value       = module.redis.url
}

output "outbound_ips" {
  description = "Addresses the environment's outbound traffic comes from."
  value       = module.network.nat_public_ips
}

output "image_repository_url" {
  description = "Where to push the service's image: docker push <this>:<tag>."
  value       = aws_ecr_repository.api.repository_url
}

output "workload_role_arns" {
  description = "Roles of the cluster add-ons and the service, by namespace/service account (EKS Pod Identity binds them; no annotation needed)."
  value = {
    "secop-analyst/api"                        = module.api_identity.role_arn
    "external-secrets/external-secrets"        = module.external_secrets_identity.role_arn
    "kube-system/aws-load-balancer-controller" = module.load_balancer_controller_identity.role_arn
    "kube-system/cluster-autoscaler"           = module.cluster_autoscaler_identity.role_arn
  }
}
