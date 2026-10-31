/*
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
  default = "data engineering"
}

variable "dataset_name" {
  type = string

}

variable "bucket_use" {
  type = string
  default = "raw-data"
}
*/

variable "project" {
  description = "Project identifier used in every resource name."
  type        = string
  default     = "cob"
}

variable "environment" {
  description = "Deployment environment. Drives naming and sizing."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either dev or prod."
  }
}

variable "owner" {
  description = "Team accountable for this stack. Applied as a tag."
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-north-1"
}

variable "lifecycle_days" {
  description = "Days before objects and old versions expire."
  type        = number

  validation {
    condition     = var.lifecycle_days > 0
    error_message = "lifecycle_days must be greater than zero."
  }
}

variable "crawler_schedule" {
  description = "Cron expression for the Glue crawler, in Glue's schedule syntax."
  type        = string
}

variable "dataset_name" {
  type = string

}