output "raw_data_bucket_name" {
  value = module.raw_data.bucket_name
}

output "raw_data_bucket_arn" {
  value = module.raw_data.bucket_arn
}

output "glue_database_name" {
  value = module.analytics.glue_database_name
}

output "glue_database_arn" {
  value = module.analytics.glue_database_arn
}

output "athena_workgroup_name" {
  value = module.analytics.athena_workgroup_name
}

output "athena_workgroup_arn" {
  value = module.analytics.athena_workgroup_arn
}

output "athena_results_bucket_arn" {
  value = module.analytics.results_bucket_arn
}

output "crawler_name" {
  value = module.analytics.crawler_name
}