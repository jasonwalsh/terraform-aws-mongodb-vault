> A Terraform module for creating a [HashiCorp Vault](https://www.vaultproject.io/) cluster

## Contents

- [Requirements](#requirements)
- [Usage](#usage)
  - [Vault Amazon Machine Image](#vault-amazon-machine-image)
  - [Terraform](#terraform)
  - [Alerting](#alerting)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [License](#license)

## Requirements

- [Packer](https://packer.io/downloads.html)
- [Terraform](https://www.terraform.io/downloads.html)

## Usage

This repository contains a Packer [template](https://www.packer.io/docs/templates/index.html) and Terraform [configurations](https://www.terraform.io/docs/configuration/index.html) for creating and provisioning a [HashiCorp Vault](https://www.vaultproject.io/) cluster.

**Note:** Before running any Packer or Terraform commands, ensure that the following environment variables are assigned:

| Name | Description |
|------|-------------|
| `AWS_ACCESS_KEY_ID` | Specifies an AWS access key associated with an IAM user or role |
| `AWS_SECRET_ACCESS_KEY` | Specifies the secret key associated with the access key |
| `AWS_DEFAULT_REGION` | Specifies the AWS Region to send the request to |

See [environment variables](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html) for more details.

> What is HashiCorp Vault?

HashiCorp Vault is software for managing secrets and protecting sensitive data. To learn more about Vault, visit the official [documentation](https://www.vaultproject.io/docs/).

> What are the use cases of HashiCorp Vault?

#### Secrets Management

Vault centrally manages and enforces access to secrets and systems based on trusted sources of application and user identity.

#### Data Encryption

Vault provides encryption as a service with centralized key management to simplify encrypting data in transit and at rest across clouds and datacenters.

### Vault Amazon Machine Image

This module assumes that an [Amazon Machine Image](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html) (AMI) exists in the Amazon account used by the [Terraform AWS Provider](https://www.terraform.io/docs/providers/aws/index.html). The [packer](packer) subdirectory contains a Packer template for building an AMI with the following software installed:

- [HashiCorp Vault](https://www.vaultproject.io/)
- [Amazon CloudWatch Agent](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html) (metrics and logging aggregation)

Before invoking **any** Terraform commands the AMI **must** exist in the AWS account used by Terraform.

For instructions on building the AMI using Packer, visit the README in the [packer](packer) subdirectory.

### Terraform

After building the AMI described in the [Vault Amazon Machine Image](#vault-amazon-machine-image) section, invoke the following Terraform commands:

    $ terraform init
    $ terraform apply

For a complete list of available inputs, see the [Inputs](#inputs) section.

### Alerting

This module uses the [`notify-slack`](https://registry.terraform.io/modules/terraform-aws-modules/notify-slack/aws) Terraform module to send messages to Slack workspaces when a [CloudWatch Alarm](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html) is triggered. The alarms for this module are configured [here](https://github.com/jasonwalsh/terraform-aws-mongodb-vault/blob/master/main.tf#L10-L30) and are changeable.

To enable alerting, create an [incoming webhook](https://api.slack.com/incoming-webhooks) in Slack. After creating the incoming wekbook, invoke `terraform apply` with the following variables:

| Name | Description | Type |
|------|-------------|:----:|
| channel | Channel, private group, or IM channel to send message to | string |
| username | Set your bot's user name | string |
| webhook\_url | The Incoming Webhook URL | string |

    $ terraform apply \
      -var 'channel=vault-alarms' \
      -var 'username=vault-bot' \
      -var 'webhook_url=https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX'

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| channel | Channel, private group, or IM channel to send message to | string | `""` | no |
| cidr\_block | The IPv4 network range for the VPC, in CIDR notation | string | `"10.0.0.0/16"` | no |
| desired\_capacity | The number of Amazon EC2 instances that the Auto Scaling group attempts to maintain | number | `"null"` | no |
| domain\_name | Fully qualified domain name (FQDN), such as www.example.com, that you want to secure with an ACM certificate | string | `"vault.corp.mongodb.com"` | no |
| hosted\_zone\_id | The ID of the hosted zone that you want to create the record in | string | `"ZYSJTA7XCIHDB"` | no |
| hosted\_zone\_name | The name of the domain for the hosted zone where you want to add the resource record set | string | `"vault.route53.build.10gen.cc"` | no |
| ingress\_ips | Allow traffic from the specified IPv4 or IPv6 CIDR addresses | list(string) | `[ "0.0.0.0/0" ]` | no |
| instance\_type | Specifies the instance type of the EC2 instance | string | `"m5.2xlarge"` | no |
| key\_name | Provides the name of the EC2 key pair | string | `""` | no |
| max\_size | The maximum number of Amazon EC2 instances in the Auto Scaling group | number | n/a | yes |
| min\_size | The minimum number of Amazon EC2 instances in the Auto Scaling group | number | n/a | yes |
| provisioned\_throughput | Throughput for the specified table, which consists of values for ReadCapacityUnits and WriteCapacityUnits | map(number) | `{ "read_capacity_units": 10, "write_capacity_units": 10 }` | no |
| retention\_in\_days | The number of days to retain the log events in the specified log group | number | `"7"` | no |
| subnets | The IDs of the subnets for the load balancer | list(string) | `[]` | no |
| tags | Adds or overwrites the specified tags for the specified resources | map(string) | `{}` | no |
| username | Set your bot's user name | string | `""` | no |
| vpc\_id | The ID of the VPC | string | `""` | no |
| vpc\_zone\_identifier | A list of subnet IDs for a virtual private cloud | list(string) | `[]` | no |
| webhook\_url | The Incoming Webhook URL | string | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| dashboard | URL to launch the CloudWatch dashboard for monitoring |
| dns\_name | The DNS name of the load balancer |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->

## License

[MIT License](LICENSE)
