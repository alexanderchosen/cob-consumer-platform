# provider.tf
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project = var.project
      Environment = var.environment
      Owner = var.owner
    }
  }
}