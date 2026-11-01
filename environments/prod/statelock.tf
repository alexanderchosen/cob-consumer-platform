terraform {
  backend "s3" {
    bucket       = "alexander-cob-tfstate-2026"
    key          = "data-platform/prod/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}