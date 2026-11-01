module "lake" {
  source = "git::https://github.com/alexanderchosen/cob-modules-platform.git//modules/s3?ref=v1.0.0"

  name_prefix         = "${var.project}-${var.environment}-s3"
  purpose             = "datalake"
  data_classification = "internal"
  enable_versioning   = true
  lifecycle_days      = var.lifecycle_days
}


# Seed datasets
locals {
  datasets = {
    orders    = "orders.csv"
    customers = "customers.csv"
    products  = "products.csv"
  }
}

resource "aws_s3_object" "seed" {
  for_each = local.datasets
  bucket   = module.lake.bucket_name
  key      = "raw/${each.key}/${each.value}"
  source   = "${path.module}/../../docs/test_data/${each.value}"
  etag     = filemd5("${path.module}/../../docs/test_data/${each.value}")
}



# Analytics layer
module "analytics" {
  source             = "git::https://github.com/alexanderchosen/cob-modules-platform.git//modules/data-platform?ref=v1.0.0"
  name_prefix        = "${var.project}-${var.environment}-data"
  purpose            = "retail-analytics"
  source_bucket_arn  = module.lake.bucket_arn
  source_bucket_name = module.lake.bucket_name
  source_prefix      = "raw/"
  crawler_schedule   = var.crawler_schedule


  depends_on = [aws_s3_object.seed]
}
