terraform {
  required_providers {
    aws = {
      version = "~>4"
      source  = "hashicorp/aws"
    }
  }
  required_version = "~>1"
}

provider "aws" {
  region = "us-east-2"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.2"

  name = "k8slab"
  cidr = "10.0.1.0/24"

  azs             = ["us-east-2a", "us-east-2b"]
  public_subnets  = ["10.0.1.0/27", "10.0.1.32/27"]
  public_subnet_tags = {
    "role" = "public"
  }
  private_subnets = ["10.0.1.64/27", "10.0.1.96/27"]
  private_subnet_tags = {
    "role" = "private"
  }

  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    "repo" = "yardbirdsax/infra-k8slab"
  }
}
