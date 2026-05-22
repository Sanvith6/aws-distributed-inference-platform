terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Default Provider (Free Tier Account)
# Expects standard AWS authentication in the terminal (AWS_ACCESS_KEY_ID, aws configure, etc.)
provider "aws" {
  region = var.aws_region
}

# Paid Account Provider (For Inference Node)
# Expects keys passed via variables (TF_VAR_paid_access_key and TF_VAR_paid_secret_key)
provider "aws" {
  alias      = "paid"
  region     = var.aws_region
  access_key = var.paid_access_key
  secret_key = var.paid_secret_key
}
