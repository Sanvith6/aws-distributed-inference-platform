variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "paid_access_key" {
  description = "Access key for the paid account (Set via TF_VAR_paid_access_key)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "paid_secret_key" {
  description = "Secret key for the paid account (Set via TF_VAR_paid_secret_key)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for Free Tier VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for Public Subnet (Free Tier)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for Private Subnet (Free Tier)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_types" {
  description = "Instance sizes mapped to roles"
  type        = map(string)
  default = {
    engine    = "t3.micro"
    caller    = "t3.micro"
    inference = "c7i-flex.large" # Production-grade constrained-compute worker
    nat       = "t3.micro"
  }
}

variable "my_ip" {
  description = "Your public IP for SSH access (e.g., '1.2.3.4/32'). Default is 0.0.0.0/0 but should be restricted."
  type        = string
  default     = "0.0.0.0/0"
}
