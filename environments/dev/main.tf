/*
module "raw_data" {
  source = "git::https://github.com/alexanderchosen/cob-modules-platform.git//modules/s3?ref=v1.0.0"
  name_prefix  = "${var.project}-${var.environment}-s3"
  purpose = var.bucket_use
  data_classification = "internal"
}

resource "aws_s3_object" "students" {
  bucket = module.raw_data.bucket_name
  key = "school/class/student.csv"
  source = "${path.module}/../../../docs/test_data/student.csv"
  etag = filemd5("${path.module}/../../../docs/test_data/student.csv")
}

module "analytics" {
  source = "git::https://github.com/alexanderchosen/cob-modules-platform.git//modules/data-platform?ref=v1.0.0"
  name_prefix = "${var.project}-${var.environment}-data"
  purpose = var.dataset_name
  source_bucket_arn = module.raw_data.bucket_arn
  source_bucket_name = module.raw_data.bucket_name
  source_prefix = "${var.dataset_name}/"
}
*/

# ---------------------------------------------------------------
# Data lake landing bucket
# Provisioned through COB's s3 capability. Encryption, versioning,
# public-access blocking and lifecycle rules are the platform's
# decisions, not ours — we declare intent only.
# ---------------------------------------------------------------
module "lake" {
  source = "git::https://github.com/alexanderchosen/cob-modules-platform.git//modules/s3?ref=v1.0.0"

  name_prefix         = "${var.project}-${var.environment}-s3"
  purpose             = "datalake"
  data_classification = "internal"
  enable_versioning   = true
  lifecycle_days      = var.lifecycle_days
}

# ---------------------------------------------------------------
# Seed datasets
# Application data, not infrastructure — see the gap analysis in
# the README for why this correctly sits outside COB.
# ---------------------------------------------------------------
locals {
  datasets = {
    orders    = "orders.csv"
    customers = "customers.csv"
    products  = "products.csv"
  }
}

resource "aws_s3_object" "seed" {
  for_each = local.datasets
  bucket = module.lake.bucket_name
  key    = "raw/${each.key}/${each.value}"
  source = "${path.module}/../../docs/test_data/${each.value}"
  etag   = filemd5("${path.module}/../../docs/test_data/${each.value}")
}



# ---------------------------------------------------------------
# Analytics layer
# Glue database + crawler over raw/, plus an Athena workgroup with
# encrypted results. One crawler yields one table per sub-prefix.
# ---------------------------------------------------------------
module "analytics" {
  source = "git::https://github.com/alexanderchosen/cob-modules-platform.git//modules/data-platform?ref=v1.0.0"
  name_prefix        = "${var.project}-${var.environment}-data"
  purpose            = "retail-analytics"
  source_bucket_arn  = module.lake.bucket_arn
  source_bucket_name = module.lake.bucket_name
  source_prefix      = "raw/"
  crawler_schedule   = var.crawler_schedule

  # The crawler must not run before the objects exist, or it
  # catalogues an empty prefix and creates no tables.
  depends_on = [aws_s3_object.seed]
}