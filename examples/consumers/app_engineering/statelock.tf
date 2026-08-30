terraform {
  backend "s3" {
    bucket = "alexander-cob-tfstate"
    key = "examples/consumers/application-engineering/terraform.tfstate"
    region = "eu-north-1"
    encrypt = true
    use_lockfile = true
  }
}