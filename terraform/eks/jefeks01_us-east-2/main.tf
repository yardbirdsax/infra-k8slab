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

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = ["k8slab"]
  }
}

data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }
}

locals {
  partition = data.aws_partition.current.partition
  name      = "jefeks01"
}

module "eks" {
  count   = var.deploy_cluster == true ? 1 : 0
  source  = "terraform-aws-modules/eks/aws"
  version = "18.28.0"

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
  cluster_name                         = local.name
  cluster_version                      = "1.22"

  node_security_group_additional_rules = {
    # Control plane invoke Karpenter webhook
    ingress_karpenter_webhook_tcp = {
      description                   = "Control plane invoke Karpenter webhook"
      protocol                      = "tcp"
      from_port                     = 8443
      to_port                       = 8443
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  vpc_id     = data.aws_vpc.vpc.id
  subnet_ids = data.aws_subnets.subnets.ids

  eks_managed_node_groups = {
    karpenter = {
      instance_types = ["t3.medium"]

      min_size     = 1
      max_size     = 2
      desired_size = 1

      iam_role_additional_policies = [
        # Required by Karpenter
        "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
      ]
    }
  }

  tags = {
    "karpenter.sh/discovery" = local.name
  }

  create_aws_auth_configmap = true
  manage_aws_auth_configmap = true
  aws_auth_users = [
    {
      userarn  = "arn:aws:sts::326154603814:assumed-role/AWSReservedSSO_AdministratorAccess_5a9dcadf48ca82ea/josh@feiermanfamily.com"
      username = "administrators"
      groups   = ["system:masters"]
    }
  ]
  aws_auth_roles = [
    {
      rolearn  = data.aws_caller_identity.current.arn
      username = "githubactions"
      groups   = ["system:masters"]
    }
  ]
}

module "karpenter_irsa" {
  count   = var.deploy_karpenter == true ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 4.21.1"

  role_name                          = "karpenter-controller-${local.name}"
  attach_karpenter_controller_policy = true

  karpenter_controller_cluster_id = module.eks[0].cluster_id
  karpenter_controller_ssm_parameter_arns = [
    "arn:${local.partition}:ssm:*:*:parameter/aws/service/*"
  ]
  karpenter_controller_node_iam_role_arns = [
    module.eks[0].eks_managed_node_groups["karpenter"].iam_role_arn
  ]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks[0].oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }
}

resource "aws_iam_instance_profile" "karpenter" {
  count = var.deploy_karpenter == true ? 1 : 0
  name  = "KarpenterNodeInstanceProfile-${local.name}"
  role  = module.eks[0].eks_managed_node_groups["karpenter"].iam_role_name
}
