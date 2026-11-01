variable "project" {
  type        = string
  default     = "cob"
}

variable "environment" {
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either dev or prod."
  }
}

variable "owner" {
  type        = string
}

variable "aws_region" {
  type        = string
  default     = "eu-north-1"
}

variable "lifecycle_days" {
  type        = number

  validation {
    condition     = var.lifecycle_days > 0
    error_message = "lifecycle_days must be greater than zero."
  }
}

variable "crawler_schedule" {
  type        = string
}

variable "dataset_name" {
  type = string

}
