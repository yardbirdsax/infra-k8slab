terraform {
  required_providers {
    aws = {
      version = "~>3"
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
  version = "3.11.0"

  name = "k8slab"
  cidr = "10.0.1.0/24"

  azs            = ["us-east-2a"]
  public_subnets = ["10.0.1.0/27"]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    "repo" = "yardbirdsax/infra-k8slab"
  }
}