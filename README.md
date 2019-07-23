## Contents

- [Requirements](#requirements)
- [Usage](#usage)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [License](#license)

## Requirements

- [Terraform](https://www.terraform.io/)

## Usage

This repository contains Terraform configurations for creating and provisioning a [HashiCorp Vault](https://www.vaultproject.io/) cluster.

> What is HashiCorp Vault?

HashiCorp Vault is software for managing secrets and protecting sensitive data. To learn more about Vault, visit the official [documentation](https://www.vaultproject.io/docs/).

**Note:** Before running any Terraform commands, ensure that the following environment variables are assigned:

| Name | Description |
|------|-------------|
| `AWS_ACCESS_KEY_ID` | Specifies an AWS access key associated with an IAM user or role |
| `AWS_SECRET_ACCESS_KEY` | Specifies the secret key associated with the access key |
| `AWS_DEFAULT_REGION` | Specifies the AWS Region to send the request to |

After configuring the required environment variables, invoke the following commands:

    $ terraform init
    $ terraform apply

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| channel | Channel, private group, or IM channel to send message to | string | `""` | no |
| cidr\_block | The IPv4 network range for the VPC, in CIDR notation | string | `"10.0.0.0/16"` | no |
| desired\_capacity | The number of Amazon EC2 instances that the Auto Scaling group attempts to maintain | number | `"3"` | no |
| domain\_name | Fully qualified domain name (FQDN), such as www.example.com, that you want to secure with an ACM certificate | string | n/a | yes |
| instance\_type | The instance type of the EC2 instance | string | `"m5.2xlarge"` | no |
| key\_name | The name of the key pair | string | n/a | yes |
| tags | Adds or overwrites the specified tags for the specified resources | map(string) | `{}` | no |
| username | Set your bot's user name | string | `""` | no |
| vpc\_id | The ID of the VPC | string | `""` | no |
| webhook\_url | The Incoming Webhook URL | string | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| dns\_name | The DNS name of the load balancer |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->

## License

[MIT License](LICENSE)
