terraform {
  backend "s3" {
    bucket = "alexander-cob-tfstate"
    key = "examples/consumers/data-engineering/terraform.tfstate"
    region = "eu-north-1"
    encrypt = true
    use_lockfile = true
  }
}