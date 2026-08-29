terraform {
  backend "s3" {
    bucket       = "alexander-cob-tfstate"
    key          = "dev/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

# the use_lockfile i used here helps to prvent two apply runs from colliding