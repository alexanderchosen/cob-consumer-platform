variable "project" {
  type = string
  default = "cob"
}

variable "environment" {
  type = string

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

variable "purpose" {
  type = string
}

variable "container_image" {
  type = string
}

variable "container_port" {
  type = number
}

variable "allowed_ingress_cidr" {
  type = string
}