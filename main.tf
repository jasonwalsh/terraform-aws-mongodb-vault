terraform {
  required_version = "~> 0.12"
}

provider "aws" {
  version = "~> 2.0"
}

locals {
  conditions = [
    var.domain_name,
    aws_route53_record.route53_record.name,
    module.alb.dns_name
  ]

  policy_arns = [
    aws_iam_policy.iam_policy.arn,
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]

  prefix = "mongodb-"
  vpc_id = coalesce(var.vpc_id, module.vpc.vpc_id)
}

###########################################
# Amazon Machine Image built using Packer #
###########################################
data "aws_ami" "ami" {
  most_recent = true
  name_regex  = "^ubuntu-xenial-16.04-amd64-server-\\d+-vault$"
  owners      = ["self"]
}

data "aws_availability_zones" "availability_zones" {
  state = "available"
}

data "aws_region" "region" {}

data "aws_acm_certificate" "acm_certificate" {
  domain      = var.domain_name
  most_recent = true
  statuses    = ["ISSUED"]

  count = var.domain_name != "" ? 1 : 0
}

# https://www.vaultproject.io/docs/configuration/storage/dynamodb.html#required-aws-permissions
data "aws_iam_policy_document" "iam_policy_document" {
  statement {
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:CreateTable",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeLimits",
      "dynamodb:DescribeReservedCapacity",
      "dynamodb:DescribeReservedCapacityOfferings",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:GetItem",
      "dynamodb:GetRecords",
      "dynamodb:ListTables",
      "dynamodb:ListTagsOfResource",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt"
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

################################################################
# Vault Auto Scaling Group ingress/egress security group rules #
################################################################
resource "aws_security_group_rule" "vault" {
  cidr_blocks = [
    "0.0.0.0/0"
  ]

  from_port         = 8200
  protocol          = "tcp"
  security_group_id = aws_security_group.security_group.id
  to_port           = 8201
  type              = "ingress"
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
  policy_arn = element(local.policy_arns, count.index)
  role       = aws_iam_role.iam_role.name

  count = length(local.policy_arns)
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
  read_capacity  = lookup(var.provisioned_throughput, "read_capacity_units", 10)
  write_capacity = lookup(var.provisioned_throughput, "write_capacity_units", 10)
}

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "3.0.0"

  associate_public_ip_address = var.key_name != "" ? true : false
  desired_capacity            = var.desired_capacity
  health_check_type           = "EC2"
  iam_instance_profile        = aws_iam_instance_profile.iam_instance_profile.name
  image_id                    = data.aws_ami.ami.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  max_size                    = var.desired_capacity
  min_size                    = var.desired_capacity
  name                        = format("%s%s", local.prefix, "vault")

  # If the launch configuration for the auto scaling group changes, then a new auto scaling group is deployed. This
  # strategy is similar to a canary deployment.
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
      # The Vault agent configuration file
      config = base64encode(
        templatefile(
          "${path.module}/templates/configuration.hcl",
          {
            kms_key_id = aws_kms_key.kms_key.key_id
            region     = data.aws_region.region.name
          }
        )
      )

      # The CloudWatch agent configuration file
      cloudwatch = base64encode(file("${path.module}/templates/amazon-cloudwatch-agent.json"))
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

  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]

    from_port = 443
    protocol  = "tcp"
    to_port   = 443
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

  https_listeners = [
    {
      certificate_arn = join("", data.aws_acm_certificate.acm_certificate.*.arn)
      port            = 443
    }
  ]

  https_listeners_count = 1
  load_balancer_name    = format("%s%s", local.prefix, "vault")
  logging_enabled       = false

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = module.vpc.public_subnets

  target_groups = [
    {
      name             = format("%s%s", local.prefix, "vault")
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
    health_check_path                = "/v1/sys/health?standbyok=true&perfstandbyok=true"
    health_check_port                = "traffic-port"
    health_check_timeout             = 5
    health_check_unhealthy_threshold = 3
    slow_start                       = 0
    stickiness_enabled               = true
    target_type                      = "instance"
  }

  vpc_id = local.vpc_id
}

resource "aws_route53_record" "route53_record" {
  alias {
    evaluate_target_health = false
    name                   = module.alb.dns_name
    zone_id                = module.alb.load_balancer_zone_id
  }

  name    = "vault.route53.build.10gen.cc"
  type    = "A"
  zone_id = "ZYSJTA7XCIHDB"
}

resource "aws_lb_listener_rule" "http" {
  action {
    redirect {
      host        = var.domain_name
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }

    target_group_arn = element(module.alb.target_group_arns, 0)
    type             = "redirect"
  }

  condition {
    field  = "host-header"
    values = [element(local.conditions, count.index)]
  }

  listener_arn = element(module.alb.http_tcp_listener_arns, 0)

  count = length(local.conditions)
}

resource "aws_lb_listener_rule" "https" {
  action {
    redirect {
      host        = var.domain_name
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }

    target_group_arn = element(module.alb.target_group_arns, 0)
    type             = "redirect"
  }

  condition {
    field  = "host-header"
    values = [aws_route53_record.route53_record.name]
  }

  listener_arn = element(module.alb.https_listener_arns, 0)
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

module "slack" {
  source  = "terraform-aws-modules/notify-slack/aws"
  version = "2.0.0"

  create            = var.webhook_url != "" ? true : false
  slack_channel     = var.channel
  slack_username    = var.username
  slack_webhook_url = var.webhook_url
  sns_topic_name    = format("%s%s", local.prefix, "vault")
}

resource "aws_cloudwatch_metric_alarm" "autoscaling" {
  alarm_actions = [
    module.slack.this_slack_topic_arn
  ]

  alarm_name          = format("%s%s-%s", local.prefix, "vault", "GroupInServiceInstances")
  comparison_operator = "LessThanThreshold"

  dimensions = {
    AutoScalingGroupName = module.autoscaling.this_autoscaling_group_name
  }

  evaluation_periods = 1
  metric_name        = "GroupInServiceInstances"
  namespace          = "AWS/AutoScaling"
  period             = 60
  statistic          = "Sum"
  tags               = var.tags
  threshold          = var.desired_capacity
}

#########################################
# Amazon CloudWatch Dashboard Resources #
#########################################
resource "aws_cloudwatch_dashboard" "cloudwatch_dashboard" {
  dashboard_body = jsonencode({
    widgets = [
      # Aggregate metrics for CPU, memory, and disk space usage for the Vault Auto Scaling Group
      {
        height = 6
        properties = {
          metrics = [
            ["CWAgent", "mem_used_percent", "AutoScalingGroupName", module.autoscaling.this_autoscaling_group_name],
            [".", "cpu_usage_system", ".", "."],
            [".", "disk_used_percent", ".", "."]
          ]
          period  = 300
          region  = data.aws_region.region.name
          stacked = false
          view    = "singleValue"
        }
        type  = "metric"
        width = 6
        x     = 0
        y     = 0
      }
    ]
  })

  dashboard_name = format("%s%s", local.prefix, "vault")
}
