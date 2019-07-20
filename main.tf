terraform {
  required_version = "~> 0.12"
}

locals {
  ports = [
    8200,
    8201
  ]

  prefix = "mongodb-"
  vpc_id = coalesce(var.vpc_id, module.vpc.vpc_id)
}

data "aws_ami" "ami" {
  most_recent = true
  name_regex  = "^amzn2-ami-hvm-\\d+-x86_64-gp2-vault$"
  owners      = ["self"]
}

data "aws_availability_zones" "availability_zones" {
  state = "available"
}

data "aws_region" "region" {}

# https://www.vaultproject.io/docs/configuration/storage/dynamodb.html#required-aws-permissions
data "aws_iam_policy_document" "iam_policy_document" {
  statement {
    actions = [
      "dynamodb:DescribeLimits",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:ListTagsOfResource",
      "dynamodb:DescribeReservedCapacityOfferings",
      "dynamodb:DescribeReservedCapacity",
      "dynamodb:ListTables",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:CreateTable",
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:GetRecords",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
      "dynamodb:Scan",
      "dynamodb:DescribeTable",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey"
    ]

    effect = "Allow"

    resources = [
      aws_dynamodb_table.dynamodb_table.arn,
      aws_kms_key.kms_key.arn
    ]
  }
}

resource "aws_kms_key" "kms_key" {
  tags = var.tags
}

resource "aws_security_group" "security_group" {
  tags   = var.tags
  vpc_id = local.vpc_id
}

# Vault-specific TCP ports
resource "aws_security_group_rule" "vault" {
  cidr_blocks = [
    "0.0.0.0/0"
  ]

  from_port         = element(local.ports, count.index)
  protocol          = "tcp"
  security_group_id = aws_security_group.security_group.id
  to_port           = element(local.ports, count.index)
  type              = "ingress"

  count = length(local.ports)
}

resource "aws_security_group_rule" "ingress" {
  cidr_blocks = [
    "0.0.0.0/0"
  ]

  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.security_group.id
  to_port           = 22
  type              = "ingress"

  count = var.key_name != "" ? 1 : 0
}

resource "aws_security_group_rule" "egress" {
  cidr_blocks = [
    "0.0.0.0/0"
  ]

  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.security_group.id
  to_port           = 0
  type              = "egress"
}

resource "aws_iam_role" "iam_role" {
  assume_role_policy = file("${path.module}/templates/policy.json")
  tags               = var.tags
}

resource "aws_iam_policy" "iam_policy" {
  policy = data.aws_iam_policy_document.iam_policy_document.json
}

resource "aws_iam_role_policy_attachment" "iam_role_policy_attachment" {
  policy_arn = aws_iam_policy.iam_policy.arn
  role       = aws_iam_role.iam_role.name
}

resource "aws_iam_instance_profile" "iam_instance_profile" {
  role = aws_iam_role.iam_role.name
}

resource "aws_dynamodb_table" "dynamodb_table" {
  attribute {
    name = "Path"
    type = "S"
  }

  attribute {
    name = "Key"
    type = "S"
  }

  billing_mode   = "PROVISIONED"
  hash_key       = "Path"
  name           = "vault-dynamodb-backend"
  range_key      = "Key"
  read_capacity  = 10
  write_capacity = 10
}

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "3.0.0"

  associate_public_ip_address  = var.key_name != "" ? true : false
  desired_capacity             = var.desired_capacity
  health_check_type            = "EC2"
  iam_instance_profile         = aws_iam_instance_profile.iam_instance_profile.name
  image_id                     = data.aws_ami.ami.id
  instance_type                = var.instance_type
  key_name                     = var.key_name
  max_size                     = var.desired_capacity
  min_size                     = var.desired_capacity
  name                         = format("%s%s", local.prefix, "vault")
  recreate_asg_when_lc_changes = true

  security_groups = [
    aws_security_group.security_group.id
  ]

  target_group_arns = [
    element(module.alb.target_group_arns, 0)
  ]

  tags_as_map = var.tags

  user_data = templatefile(
    "${path.module}/templates/user-data.txt",
    {
      # The Vault agent configuration
      config = base64encode(
        templatefile(
          "${path.module}/templates/configuration.tf",
          {
            kms_key_id = aws_kms_key.kms_key.key_id
            region     = data.aws_region.region.name
          }
        )
      ),
      # The systemd unit configuration
      systemd = base64encode(file("${path.module}/templates/vault.service"))
    }
  )

  vpc_zone_identifier = var.key_name != "" ? module.vpc.public_subnets : module.vpc.private_subnets
}

resource "aws_security_group" "alb" {
  egress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]

    from_port = 0
    protocol  = "-1"
    to_port   = 0
  }
  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]

    from_port = 80
    protocol  = "tcp"
    to_port   = 80
  }

  vpc_id = local.vpc_id
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "4.1.0"

  http_tcp_listeners = [
    {
      port     = 80
      protocol = "HTTP"
    }
  ]

  http_tcp_listeners_count = 1
  load_balancer_name       = format("%s%s", local.prefix, "vault")
  logging_enabled          = false

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = module.vpc.public_subnets

  target_groups = [
    {
      name             = "vault"
      backend_protocol = "HTTPS"
      backend_port     = 8200
    }
  ]

  target_groups_count = 1

  target_groups_defaults = {
    cookie_duration                  = 86400
    deregistration_delay             = 300
    health_check_healthy_threshold   = 3
    health_check_interval            = 10
    health_check_matcher             = "200-299"
    health_check_path                = "/v1/sys/health?standbyok=true"
    health_check_port                = "traffic-port"
    health_check_timeout             = 5
    health_check_unhealthy_threshold = 3
    slow_start                       = 0
    stickiness_enabled               = true
    target_type                      = "instance"
  }

  vpc_id = local.vpc_id
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.5.0"

  azs                     = data.aws_availability_zones.availability_zones.names
  cidr                    = var.cidr_block
  create_vpc              = var.vpc_id == "" ? true : false
  enable_dns_hostnames    = true
  enable_nat_gateway      = true
  map_public_ip_on_launch = var.key_name != "" ? true : false
  name                    = format("%s%s", local.prefix, "vault")

  private_subnets = [
    "10.0.0.0/24",
    "10.0.1.0/24"
  ]

  public_subnets = [
    "10.0.2.0/24",
    "10.0.3.0/24"
  ]

  tags = var.tags
}
