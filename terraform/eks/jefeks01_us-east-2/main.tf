terraform {
  required_providers {
    aws = {
      version = "~>4"
      source  = "hashicorp/aws"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "~>0.25"
    }
  }
  required_version = "~>1"
}

provider "aws" {
  region = "us-east-2"
}

provider "kubernetes" {
  host = module.eks[0].cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks[0].cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command = "aws"
    args = [
      "eks", "get-token", "--cluster-name", module.eks[0].cluster_name
    ]
  }
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = ["k8slab"]
  }
}

data "aws_subnets" "public_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }
  filter {
    name   = "tag:role"
    values = ["public"]
  }
}

data "aws_subnets" "private_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }
  filter {
    name   = "tag:role"
    values = ["private"]
  }
}

locals {
  partition = data.aws_partition.current.partition
  name      = "jefeks01_us-east-2"
}

module "eks" {
  count   = var.deploy_cluster == true ? 1 : 0
  source  = "terraform-aws-modules/eks/aws"
  version = "19.13.0"

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
  cluster_name                         = local.name
  cluster_version                      = "1.26"
  create_cluster_security_group        = false
  create_node_security_group           = false

  vpc_id     = data.aws_vpc.vpc.id
  subnet_ids = data.aws_subnets.public_subnets.ids

  fargate_profiles = {
    karpenter = {
      selectors = [
        { namespace = "karpenter" }
      ]
      subnet_ids = data.aws_subnets.private_subnets.ids
    }
    kube-system = {
      selectors = [
        { namespace = "kube-system" }
      ]
      subnet_ids = data.aws_subnets.private_subnets.ids
    }
  }

  tags = {
    "karpenter.sh/discovery" = local.name
  }

  create_aws_auth_configmap = true
  manage_aws_auth_configmap = true
  aws_auth_users = [
    {
      userarn  = "arn:aws:iam::326154603814:role/AWSReservedSSO_AdministratorAccess_5a9dcadf48ca82ea"
      username = "administrators"
      groups   = ["system:masters"]
    }
  ]
  aws_auth_roles = [
    {
      rolearn  = data.aws_caller_identity.current.arn
      username = "githubactions"
      groups   = ["system:masters"]
    },
    {
      rolearn  = module.karpenter[0].role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    }
  ]
}

module "karpenter" {
  count   = var.deploy_cluster == true ? 1 : 0
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "19.13.0"

  cluster_name = module.eks[0].cluster_name

  irsa_oidc_provider_arn          = module.eks[0].oidc_provider_arn
  irsa_namespace_service_accounts = ["karpenter:karpenter"]

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}
