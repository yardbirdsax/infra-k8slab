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

locals {
  deployment_name = "awsk3s01"
  repo_slug       = "yardbirdsax/infra-k8slab"
}

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = ["k8slab"]
  }
}

resource "aws_security_group" "minecraft_bedrock" {
  name   = "minecraft"
  vpc_id = data.aws_vpc.vpc.id
  tags = {
    "repo" = local.repo_slug
    "Name" = "minecraft"
  }
}

resource "aws_security_group_rule" "minecraft_bedrock" {
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 19132
  to_port           = 19132
  security_group_id = aws_security_group.minecraft_bedrock.id
  type              = "ingress"
  protocol          = "udp"
}

resource "aws_security_group" "cluster" {
  name   = local.deployment_name
  vpc_id = data.aws_vpc.vpc.id
  tags = {
    "repo" = local.repo_slug
    "Name" = local.deployment_name
  }
}

resource "aws_security_group_rule" "egress" {
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 65535
  type              = "egress"
  protocol          = "-1"
  security_group_id = aws_security_group.cluster.id
}

resource "aws_iam_role" "role" {
  name = local.deployment_name
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : ["ec2.amazonaws.com"]
          },
          "Effect" : "Allow",
          "Sid" : ""
        }
      ]
    }
  )
  tags = {
    "repo" = local.repo_slug
  }
}

data "aws_iam_policy" "ssm" {
  name = "AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.role.name
  policy_arn = data.aws_iam_policy.ssm.arn
}

module "k3s" {
  source = "github.com/yardbirdsax/terraform-k3s-on-ec2?ref=65c117f47d9e4625b2c7f50340cee09ab13ed9fe"
  providers = {
    aws = aws
  }

  assign_public_ip = true
  deployment_name  = local.deployment_name
  instance_type    = "t4.small"
  security_group_ids = [
    aws_security_group.cluster.id,
    aws_security_group.minecraft_bedrock.id
  ]

}