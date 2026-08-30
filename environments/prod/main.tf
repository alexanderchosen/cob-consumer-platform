module "networking" {
    source = "../../modules/networking"
    name_prefix = "${var.project}-${var.environment}-net"
    nat_gateway_enable = false
}

# wildcard * is not allowed, so this should throw an error
module "test_role" {
    source = "../../modules/iam"
    name_prefix = "cob-dev-iam"
    role-use = "validation-test"
    trusted_service = "ec2"
    s3_read_arn = ["arn:aws:s3:::cob-iam-test/*"]
   }

module "test_ec2" {
    source = "../../modules/ec2"
    name_prefix = "${var.project}-${var.environment}-ec2"
    purpose = "test-ec2"
    vpc_id = module.networking.vpc_id
    subnet_id = module.networking.public_subnet_ids[0]
    allowed_ingress_cidr = var.my_ip_cidr
   }


# since it is now in the prod environment, I increased the max_size and desired_capacity to create more instances
module "my_app" {
  source = "../../modules/ecs"
  name_prefix = "${var.project}-${var.environment}-ecs"
  purpose = "webapp"
  vpc_id = module.networking.vpc_id
  subnet_ids = module.networking.public_subnet_ids
  instance_type = "t3.micro"
  min_size = 1
  max_size = 3
  desired_capacity = 2
  container_image = "public.ecr.aws/nginx/nginx:latest"
  container_port = 80
  allowed_ingress_cidr = "0.0.0.0/0"
}

module "database" {
  source = "../../modules/rds"
  name_prefix = "${var.project}-${var.environment}-rds"
  purpose = "webapp"
  vpc_id = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids
  app_security_group_id = module.my_app.instance_sg_id
}

module "raw_data" {
  source = "../../modules/s3"
  name_prefix = "${var.project}-${var.environment}-s3"
  purpose = "raw-data"
  data_classification = "internal"
}

resource "aws_s3_object" "test_customers" {
  bucket = module.raw_data.bucket_name
  key = "2026/08/29/customers.csv"
  source = "${path.module}/../../docs/test_data/customers.csv"
  etag = filemd5("${path.module}/../../docs/test_data/customers.csv")
}

module "analytics" {
  source = "../../modules/data-platform"
  name_prefix = "${var.project}-${var.environment}-data"
  purpose = "customers"
  source_bucket_arn = module.raw_data.bucket_arn
  source_bucket_name = module.raw_data.bucket_name
  source_prefix = "customers/"
}



