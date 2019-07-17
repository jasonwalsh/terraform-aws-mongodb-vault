terraform {
  required_version = "~> 0.12"
}

locals {
  prefix = "mongodb-"
}

module "vault" {
  source  = "hashicorp/vault/aws"
  version = "0.13.1"
}
