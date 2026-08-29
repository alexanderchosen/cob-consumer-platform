variable "project" {
    description = "we have a fixed project name for the dev environment"
    type = string
    default = "cob"
}

variable "environment" {
    description = "This also has a fixed deployment environment"
    type = string
    default = "prod"

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

# i noticed that without putting a value for the owner variable, it still works. So, i need to find a way to validate that a value is given, else throw an error
variable "owner" {
    description = "We need the name of the team or person using this prod environment"
    type = string
    default = "Product Testers"
}

variable "my_ip_cidr" {
  type = string
}