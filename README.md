## Contents

- [Requirements](#requirements)
- [Usage](#usage)
  - [Prerequisites](#prerequisites)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [License](#license)

## Requirements

- [Terraform](https://www.terraform.io/)

## Usage

This repository contains Terraform configurations for creating and provisioning a [HashiCorp Vault](https://www.vaultproject.io/) cluster.

> What is HashiCorp Vault?

HashiCorp Vault is software for managing secrets and protecting sensitive data. To learn more about Vault, visit the official [documentation](https://www.vaultproject.io/docs/).

### Prerequisites

This repository uses the verified AWS Vault [module](https://registry.terraform.io/modules/hashicorp/vault/aws) from the Terraform module registry. The source module is responsible for creating a Vault cluster and a [Consul](https://www.consul.io/) cluster. The Vault cluster requires Consul because the Vault servers are configured to use Consul as a [storage](https://www.vaultproject.io/docs/configuration/storage/index.html) backend. Consul also provides other useful features such as service discovery, health checks, key/value storage, and much more.

To learn more about the cluster topology, visit the official [documentation](https://github.com/hashicorp/terraform-aws-vault).

**Note:** Before running any Terraform commands, ensure that the following environment variables are assigned:

| Name | Description |
|------|-------------|
| `AWS_ACCESS_KEY_ID` | Specifies an AWS access key associated with an IAM user or role |
| `AWS_SECRET_ACCESS_KEY` | Specifies the secret key associated with the access key |
| `AWS_DEFAULT_REGION` | Specifies the AWS Region to send the request to |

    $ terraform init
    $ terraform apply

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| key\_name | The name of the key pair | string | `""` | yes |

## Outputs

| Name | Description |
|------|-------------|
| dns\_name | The public DNS name |

## License

[MIT License](LICENSE)
