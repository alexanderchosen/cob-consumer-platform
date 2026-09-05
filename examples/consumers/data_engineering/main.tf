module "raw_data" {
  source = "../../../modules/s3"
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
  source = "../../../modules/data-platform"
  name_prefix = "${var.project}-${var.environment}-data"
  purpose = var.dataset_name
  source_bucket_arn = module.raw_data.bucket_arn
  source_bucket_name = module.raw_data.bucket_name
  source_prefix = "${var.dataset_name}/"
}