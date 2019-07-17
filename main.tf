terraform {
  required_version = "~> 0.12"
}

locals {
  prefix = "mongodb-"
}

data "aws_ami" "ami" {
  most_recent = true
  name_regex  = "^amzn2-ami-hvm-\\d+-x86_64-gp2-vault$"
  owners      = ["self"]
}

module "vault" {
  source  = "hashicorp/vault/aws"
  version = "0.13.1"

  ami_id              = data.aws_ami.ami.id
  consul_cluster_name = format("%s%s", local.prefix, "consul")
  ssh_key_name        = var.key_name
  vault_cluster_name  = format("%s%s", local.prefix, "vault")
}
