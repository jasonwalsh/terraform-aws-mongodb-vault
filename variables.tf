variable "cidr_block" {
  default     = "10.0.0.0/16"
  description = "The IPv4 network range for the VPC, in CIDR notation"
  type        = string
}

variable "desired_capacity" {
  default     = 3
  description = "The number of Amazon EC2 instances that the Auto Scaling group attempts to maintain"
  type        = number
}

variable "domain_name" {
  default     = "vault.corp.mongodb.com"
  description = "Fully qualified domain name (FQDN), such as www.example.com, that you want to secure with an ACM certificate"
  type        = string
}

variable "instance_type" {
  default     = "m5.2xlarge"
  description = "The instance type of the EC2 instance"
  type        = string
}

variable "key_name" {
  default     = ""
  description = "The name of the key pair"
  type        = string
}

variable "provisioned_throughput" {
  default = {
    read_capacity_units  = 10
    write_capacity_units = 10
  }
  description = "Represents the provisioned throughput settings for a specified table or index"
  type        = map(number)
}

variable "tags" {
  default     = {}
  description = "Adds or overwrites the specified tags for the specified resources"
  type        = map(string)
}

variable "vpc_id" {
  default     = ""
  description = "The ID of the VPC"
  type        = string
}

###########################################
# Slack variables for Amazon SNS messages #
###########################################
variable "channel" {
  default     = ""
  description = "Channel, private group, or IM channel to send message to"
  type        = string
}

variable "username" {
  default     = ""
  description = "Set your bot's user name"
  type        = string
}

variable "webhook_url" {
  default     = ""
  description = "The Incoming Webhook URL"
  type        = string
}
