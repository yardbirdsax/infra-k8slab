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

  azs            = ["us-east-2a", "us-east-2b"]
  public_subnets = ["10.0.1.0/27", "10.0.1.32/27"]
  public_subnet_tags = {
    "role" = "public"
  }
  private_subnets = ["10.0.1.64/27", "10.0.1.96/27"]
  private_subnet_tags = {
    "role" = "private"
  }

  enable_dns_hostnames = true
  enable_nat_gateway   = false
  enable_vpn_gateway   = false

  tags = {
    "repo" = "yardbirdsax/infra-k8slab"
  }
}

data "aws_security_group" "default" {
  name   = "default"
  vpc_id = module.vpc.vpc_id
}

data "aws_iam_policy_document" "generic_endpoint_policy" {
  statement {
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpc"

      values = [module.vpc.vpc_id]
    }
  }
}

resource "aws_security_group" "vpc_tls" {
  name_prefix = "${module.vpc.name}-vpc_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  tags = {
    "repo" = "yardbirdsax/infra-k8slab"
  }
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "3.14.2"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [aws_security_group.vpc_tls.id]

  endpoints = {
    s3 = {
      service             = "s3"
      tags                = { Name = "s3-vpc-endpoint" }
      service_type        = "Gateway"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      route_table_ids = flatten([module.vpc.private_route_table_ids, module.vpc.public_route_table_ids])
    },
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      policy              = data.aws_iam_policy_document.generic_endpoint_policy.json
    },
    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      policy              = data.aws_iam_policy_document.generic_endpoint_policy.json
    },
    eks = {
      service             = "eks"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
  }
}
