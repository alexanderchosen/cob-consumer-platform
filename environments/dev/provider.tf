terraform {
 # required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
}
  }
}

provider "aws" {
  region = var.aws_region

# the default tags i used here ensures that every resource created under this dev environment automatically gets these tags
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner
    }
  }
}



