variable "cidr_block" {
  default     = "10.0.0.0/16"
  description = "The IPv4 network range for the VPC, in CIDR notation"
  type        = string
}

variable "desired_capacity" {
  default     = null
  description = "The number of Amazon EC2 instances that the Auto Scaling group attempts to maintain"
  type        = number
}

variable "domain_name" {
  default     = "vault.corp.mongodb.com"
  description = "Fully qualified domain name (FQDN), such as www.example.com, that you want to secure with an ACM certificate"
  type        = string
}

variable "health_check_grace_period" {
  default     = 300
  description = "The amount of time, in seconds, that Amazon EC2 Auto Scaling waits before checking the health status of an EC2 instance that has come into service"
  type        = number
}

variable "health_check_type" {
  default     = "EC2"
  description = "The service to use for the health checks"
  type        = string
}

variable "hosted_zone_id" {
  default     = "ZYSJTA7XCIHDB"
  description = "The ID of the hosted zone that you want to create the record in"
  type        = string
}

variable "hosted_zone_name" {
  default     = "vault.route53.build.10gen.cc"
  description = "The name of the domain for the hosted zone where you want to add the resource record set"
  type        = string
}

variable "instance_type" {
  default     = "m5.2xlarge"
  description = "Specifies the instance type of the EC2 instance"
  type        = string
}

variable "ingress_ips" {
  default     = ["0.0.0.0/0"]
  description = "Allow traffic from the specified IPv4 or IPv6 CIDR addresses"
  type        = list(string)
}

variable "key_name" {
  default     = ""
  description = "Provides the name of the EC2 key pair"
  type        = string
}

variable "max_size" {
  description = "The maximum number of Amazon EC2 instances in the Auto Scaling group"
  type        = number
}

variable "min_size" {
  description = "The minimum number of Amazon EC2 instances in the Auto Scaling group"
  type        = number
}

variable "provisioned_throughput" {
  default = {
    read_capacity_units  = 10
    write_capacity_units = 10
  }

  description = "Throughput for the specified table, which consists of values for ReadCapacityUnits and WriteCapacityUnits"
  type        = map(number)
}

variable "retention_in_days" {
  default     = 7
  description = "The number of days to retain the log events in the specified log group"
  type        = number
}

variable "subnets" {
  default     = []
  description = "The IDs of the subnets for the load balancer"
  type        = list(string)
}

variable "table_name" {
  default     = "vault-dynamodb-backend"
  description = "The name of the table to create"
  type        = string
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

variable "vpc_zone_identifier" {
  default     = []
  description = "A list of subnet IDs for a virtual private cloud"
  type        = list(string)
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
