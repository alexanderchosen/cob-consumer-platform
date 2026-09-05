# so, its worth noting that I learnt terraform does not execute this file from top to bottom but instead it builds a dependency graph and then figures out the correct order to create things from it

module "networking" {
    source = "../../modules/networking"
    name_prefix = "${var.project}-${var.environment}-net"
    nat_gateway_enable = false
}

# wildcard * is not allowed, so this should throw an error when it is used as the arn
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

# this is for the ecs in the dev environment
# i chose a min_size and max_size of 1, limiting the auto scaling group to a single instance
module "my_app" {
    source = "../../modules/ecs"
    name_prefix = "${var.project}-${var.environment}-ecs"
    purpose = "webapp"
    vpc_id = module.networking.vpc_id
    subnet_ids = module.networking.public_subnet_ids
    instance_type = "t3.micro"
    min_size = 1
    max_size = 1
    desired_capacity = 1
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

resource "aws_s3_object" "test_orders" {
  bucket = module.raw_data.bucket_name
  key = "orders/orders.csv"
  source = "${path.module}/../../docs/test_data/orders.csv"
  etag = filemd5("${path.module}/../../docs/test_data/orders.csv")
}

module "analytics" {
  source = "../../modules/data-platform"
  name_prefix = "${var.project}-${var.environment}-data"
  purpose = "orders"
  source_bucket_arn = module.raw_data.bucket_arn
  source_bucket_name = module.raw_data.bucket_name
  source_prefix = "orders/"
}


