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

variable "instance_type" {
  default     = "t3.medium"
  description = "The instance type of the EC2 instance"
  type        = string
}

variable "key_name" {
  description = "The name of the key pair"
  type        = string
}

variable "tags" {
  default = {}
  type    = map(string)
}

variable "vpc_id" {
  default     = ""
  description = "The ID of the VPC"
  type        = string
}
