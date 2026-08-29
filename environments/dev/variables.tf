variable "project" {
    description = "we have a fixed project name for the dev environment"
    type = string
    default = "cob"
}

variable "environment" {
    description = "This also has a fixed deployment environment"
    type = string
    default = "dev"

    validation {
      condition = contains(["dev", "prod"], var.environment)
      error_message = "The environemnt variable must be either dev or prod"
    }
}

variable "aws_region" {
    description = "This is for the aws region to deploy to"
    type = string
    default = "eu-north-1"
}

variable "owner" {
    description = "We need the name of the team or person using this dev environment"
    type = string
    default = "Web dev team"
}

variable "my_ip_cidr" {
  type = string
}