module "networking" {
    source = "../../../modules/networking"
    name_prefix = "${var.project}-${var.environment}-net"
}

module "webapp" {
  source = "../../../modules/ecs"
  name_prefix = "${var.project}-${var.environment}-ecs"
  purpose = var.purpose
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
    source = "../../../modules/rds"
    name_prefix = "${var.project}-${var.environment}-rds"
    purpose = var.purpose
    vpc_id = module.networking.vpc_id
    subnet_ids = module.networking.private_subnet_ids
    app_security_group_id  = module.webapp.instance_sg_id
}