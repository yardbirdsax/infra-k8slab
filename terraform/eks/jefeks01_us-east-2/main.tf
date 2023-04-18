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
    github = {
      source  = "integrations/github"
      version = "~>5.22"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~>2.0"
    }
  }
  required_version = "~>1"
}

provider "aws" {
  region = "us-east-2"
}

provider "kubernetes" {
  host                   = module.eks[0].cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks[0].cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
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

  cluster_addons = {
    kube-proxy = {}
    vpc-cni    = {}
    coredns = {
      configuration_values = jsonencode({
        computeType = "Fargate"
        # Ensure that we fully utilize the minimum amount of resources that are supplied by
        # Fargate https://docs.aws.amazon.com/eks/latest/userguide/fargate-pod-configuration.html
        # Fargate adds 256 MB to each pod's memory reservation for the required Kubernetes
        # components (kubelet, kube-proxy, and containerd). Fargate rounds up to the following
        # compute configuration that most closely matches the sum of vCPU and memory requests in
        # order to ensure pods always have the resources that they need to run.
        resources = {
          limits = {
            cpu = "0.25"
            # We are targetting the smallest Task size of 512Mb, so we subtract 256Mb from the
            # request/limit to ensure we can fit within that task
            memory = "256M"
          }
          requests = {
            cpu = "0.25"
            # We are targetting the smallest Task size of 512Mb, so we subtract 256Mb from the
            # request/limit to ensure we can fit within that task
            memory = "256M"
          }
        }
      })
    }
  }

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
    flux-system = {
      selectors = [
        { namespace = "flux-system" }
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

data "external" "github_token" {
  program = ["bash", "-c", "gh auth token | jq --raw-input '{token: .}'"]
}

provider "github" {
  token = data.external.github_token.result.token
  owner = "yardbirdsax"
}

resource "tls_private_key" "flux" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "github_repository_deploy_key" "this" {
  title      = "Flux"
  repository = "infra-k8slab"
  key        = tls_private_key.flux.public_key_openssh
  read_only  = "false"
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks[0].cluster_name
}

provider "flux" {
  kubernetes = {
    host                   = module.eks[0].cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks[0].cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
  git = {
    url    = "ssh://git@github.com/yardbirdsax/infra-k8slab.git"
    branch = "eks"
    ssh = {
      username    = "git"
      private_key = tls_private_key.flux.private_key_pem
    }
  }
}

resource "flux_bootstrap_git" "flux" {
  path = "clusters/${module.eks[0].cluster_name}"
}
