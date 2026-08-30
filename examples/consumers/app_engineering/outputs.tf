output "vpc_id" {
  value = module.networking.vpc_id
}

output "ecs_cluster_name" {
  value = module.webapp.cluster_name
}

output "ecs_service_name" {
  value = module.webapp.service_name
}

output "db_endpoint" {
  value = module.database.db_endpoint
}

output "db_credentials_secret_arn" {
  value = module.database.credentials_secret_arn
}