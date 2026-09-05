variable "project" {
  type = string
  default = "cob"
}

variable "environment" {
  type = string
  default = "dev"

  validation {
    condition = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either dev or prod."
  }
}

variable "aws_region" {
  type = string
  default = "eu-north-1"
}

variable "owner" {
  type = string
  default = "application engineering"
}