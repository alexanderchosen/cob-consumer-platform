output "vpc_id" {
  value = module.networking.vpc_id
}

output "webapp_public_ip" {
  value = "aws ec2 describe-instances --filters Name=tag:Name,Values=${var.project}-${var.environment}-ecs-webapp-instance"
}

output "raw_data_bucket_name" {
  value = module.raw_data.bucket_name
}

output "glue_database_name" {
  value = module.analytics.glue_database_name
}

output "athena_workgroup_name" {
  value = module.analytics.athena_workgroup_name
}

output "db_endpoint" {
  value = module.database.db_endpoint
}
