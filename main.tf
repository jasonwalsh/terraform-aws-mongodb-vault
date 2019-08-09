terraform {
  backend "s3" {
    bucket = "terraform-mongodb-vault"
    key    = "terraform.tfstate"
  }

  required_version = "~> 0.12"
}

provider "aws" {
  version = "~> 2.0"
}

locals {
  ############################
  # Amazon CloudWatch Alarms #
  ############################

  # Update the elements in this list to configure thresholds for CloudWatch alarms. Metrics are collected via the
  # CloudWatch agent installed on each EC2 instance in the Auto Scaling Group.
  #
  # To view a list of aggregated metrics, refer to the `amazon-cloudwatch-agent.json` configuration file in the
  # `templates` directory.
  #
  # For more information on CloudWatch alarms, refer to the official AWS documentation:
  #
  # https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html

  alarms = [
    {
      comparison_operator = "GreaterThanOrEqualToThreshold"
      metric_name         = "cpu_usage_system"
      statistic           = "Average"
      threshold           = 75
    },
    {
      comparison_operator = "GreaterThanOrEqualToThreshold"
      metric_name         = "mem_used_percent"
      statistic           = "Average"
      threshold           = 75
    },

    {
      comparison_operator = "GreaterThanOrEqualToThreshold"
      metric_name         = "disk_used_percent"
      statistic           = "Average"
      threshold           = 75
    }
  ]

  alarm_actions = coalescelist(
    list(module.slack.this_slack_topic_arn),
    list("")
  )

  ####################################
  # ALB HTTP listener redirect rules #
  ####################################

  # The `conditions` list contains host names to route to the ALB HTTPS listener. The current host names are:
  #
  # · vault.corp.mongodb.com
  # · vault.route53.build.10gen.cc
  # · The DNS name associated with the ALB

  conditions = [
    var.domain_name,
    aws_route53_record.route53_record.name,
    module.alb.dns_name
  ]

  desired_capacity = coalesce(var.desired_capacity, var.min_size)

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

# The image used by Terraform is _always_ the most recent image.
data "aws_ami" "ami" {
  most_recent = true
  name_regex  = "^hashicorp-vault-\\d+$"
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

  lifecycle {
    create_before_destroy = true
  }
}

################################################################
# Vault Auto Scaling Group ingress/egress security group rules #
################################################################

resource "aws_security_group_rule" "vault" {
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 8200
  protocol          = "tcp"
  security_group_id = aws_security_group.security_group.id
  to_port           = 8201
  type              = "ingress"
}

resource "aws_security_group_rule" "ingress" {
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.security_group.id
  to_port           = 22
  type              = "ingress"

  count = var.key_name != "" ? 1 : 0
}

resource "aws_security_group_rule" "egress" {
  cidr_blocks       = ["0.0.0.0/0"]
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

  billing_mode = "PROVISIONED"
  hash_key     = "Path"
  name         = var.table_name

  point_in_time_recovery {
    enabled = true
  }

  range_key      = "Key"
  read_capacity  = lookup(var.provisioned_throughput, "read_capacity_units", 10)
  write_capacity = lookup(var.provisioned_throughput, "write_capacity_units", 10)
}

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "3.0.0"

  associate_public_ip_address = var.key_name != "" ? true : false
  desired_capacity            = local.desired_capacity
  health_check_type           = var.health_check_type
  health_check_grace_period   = var.health_check_grace_period
  iam_instance_profile        = aws_iam_instance_profile.iam_instance_profile.name
  image_id                    = data.aws_ami.ami.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  max_size                    = var.max_size
  min_size                    = var.min_size
  name                        = format("%s%s", local.prefix, "vault")

  # If the launch configuration for the auto scaling group changes, then a new auto scaling group is deployed. This
  # strategy is similar to a canary deployment.
  recreate_asg_when_lc_changes = true

  root_block_device = [
    {
      volume_size = 50
      volume_type = "gp2"
    }
  ]

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
            api_addr   = format("https://%s:443", var.domain_name)
            kms_key_id = aws_kms_key.kms_key.key_id
            region     = data.aws_region.region.name
            table      = aws_dynamodb_table.dynamodb_table.name
          }
        )
      )

      # The CloudWatch agent configuration file
      cloudwatch = base64encode(
        templatefile(
          "${path.module}/templates/amazon-cloudwatch-agent.json",
          {
            log_group_name = aws_cloudwatch_log_group.cloudwatch_log_group.name
          }
        )
      )
    }
  )

  # If the `vpc_zone_identifier` variable is not provided, then use either the public or private subnets created via the
  # VPC module. If the EC2 instances in the auto scaling group require SSH access, then use the public subnets,
  # otherwise, use the private subnets.
  vpc_zone_identifier = coalescelist(
    var.vpc_zone_identifier,
    (var.key_name != "" ? module.vpc.public_subnets : module.vpc.private_subnets)
  )
}

resource "aws_security_group" "alb" {
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  ingress {
    cidr_blocks = var.ingress_ips
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
  }

  ingress {
    cidr_blocks = var.ingress_ips
    from_port   = 443
    protocol    = "tcp"
    to_port     = 443
  }

  vpc_id = local.vpc_id

  lifecycle {
    create_before_destroy = true
  }
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

  subnets = coalescelist(var.subnets, module.vpc.public_subnets)

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
    deregistration_delay             = 10
    health_check_healthy_threshold   = 3
    health_check_interval            = 10
    health_check_matcher             = "200-299"
    health_check_path                = format("/v1/sys/health%s", var.health_check_type == "EC2" ? "" : "?standbyok=true")
    health_check_port                = "traffic-port"
    health_check_timeout             = 5
    health_check_unhealthy_threshold = local.desired_capacity - 1
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

  name    = var.hosted_zone_name
  type    = "A"
  zone_id = var.hosted_zone_id
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

#############################################################
# Amazon Auto Scaling Group EC2 instances CloudWatch alarms #
#############################################################

resource "aws_cloudwatch_metric_alarm" "cloudwatch_metric_alarm" {
  alarm_actions       = local.alarm_actions
  alarm_name          = replace(format("%s%s-%s", local.prefix, "vault", lookup(local.alarms[count.index], "metric_name")), "_", "-")
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    AutoScalingGroupName = module.autoscaling.this_autoscaling_group_name
  }

  evaluation_periods = 1
  metric_name        = lookup(local.alarms[count.index], "metric_name")
  namespace          = "CWAgent"
  period             = 60
  statistic          = lookup(local.alarms[count.index], "statistic", "Average")
  tags               = var.tags
  threshold          = lookup(local.alarms[count.index], "threshold", 75)

  count = length(local.alarms)
}

#########################################
# Amazon CloudWatch Dashboard Resources #
#########################################

resource "aws_cloudwatch_dashboard" "cloudwatch_dashboard" {
  dashboard_body = jsonencode({
    widgets = [
      # Aggregate metrics for CPU, memory, and disk space usage for the Vault Auto Scaling Group
      {
        height = 3
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
        width = 15
        x     = 0
        y     = 0
      },
      {
        height = 3
        properties = {
          metrics = [
            ["CWAgent", "net_bytes_recv", "AutoScalingGroupName", module.autoscaling.this_autoscaling_group_name],
            [".", "net_bytes_sent", ".", "."]
          ]
          period  = 300
          region  = data.aws_region.region.name
          stacked = false
          view    = "singleValue"
        }
        type  = "metric"
        width = 15
        x     = 0
        y     = 3
      },
      {
        height = 3
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.dynamodb_table.name],
            [".", "ConsumedReadCapacityUnits", ".", "."]
          ]
          period  = 300
          region  = data.aws_region.region.name
          stacked = false
          view    = "singleValue"
        }
        type  = "metric"
        width = 15
        x     = 0
        y     = 6
      }
    ]
  })

  dashboard_name = format("%s%s", local.prefix, "vault")
}

#######################################
# Amazon CloudWatch logging resources #
#######################################

resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = format("/aws/autoscaling/%svault", local.prefix)
  retention_in_days = var.retention_in_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_metric_filter" "cloudwatch_log_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloudwatch_log_group.name

  metric_transformation {
    default_value = 0
    name          = "sealed"
    namespace     = "LogMetrics"
    value         = 1
  }

  name    = "sealed"
  pattern = "\"core: vault is sealed\""
}

resource "aws_cloudwatch_metric_alarm" "sealed" {
  alarm_actions       = local.alarm_actions
  alarm_description   = "A Vault server has entered a sealed state. Please contact a Vault operator to administer an unseal of the Vault server."
  alarm_name          = format("%s%s-%s", local.prefix, "vault", "sealed")
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "sealed"
  namespace           = "LogMetrics"
  period              = 60
  statistic           = "Sum"
  tags                = var.tags
  threshold           = local.desired_capacity
}

#####################################
# Amazon CloudWatch DynamoDB alarms #
#####################################

resource "aws_cloudwatch_metric_alarm" "consumed_read_capacity_units" {
  alarm_actions       = local.alarm_actions
  alarm_name          = format("%s%s-%s", local.prefix, "vault", "consumed-read-capacity-units")
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    TableName = aws_dynamodb_table.dynamodb_table.name
  }

  evaluation_periods = 1
  metric_name        = "ConsumedReadCapacityUnits"
  namespace          = "AWS/DynamoDB"
  period             = 60
  statistic          = "Sum"
  tags               = var.tags
  threshold          = var.provisioned_throughput["read_capacity_units"]
}

resource "aws_cloudwatch_metric_alarm" "consumed_write_capacity_units" {
  alarm_actions       = local.alarm_actions
  alarm_name          = format("%s%s-%s", local.prefix, "vault", "consumed-write-capacity-units")
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    TableName = aws_dynamodb_table.dynamodb_table.name
  }

  evaluation_periods = 1
  metric_name        = "ConsumedWriteCapacityUnits"
  namespace          = "AWS/DynamoDB"
  period             = 60
  statistic          = "Sum"
  tags               = var.tags
  threshold          = var.provisioned_throughput["write_capacity_units"]
}
