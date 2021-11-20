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
}

resource "aws_security_group_rule" "minecraft_bedrock" {
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 19132
  to_port           = 19132
  security_group_id = aws_security_group.minecraft_bedrock.id
  type              = "ingress"
  protocol          = "udp"
}

resource "aws_security_group" "awsk3s01" {
  name   = local.deployment_name
  vpc_id = data.aws_vpc.vpc.id
}

resource "aws_security_group_rule" "awsk3s01_egress" {
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 65535
  type              = "egress"
  protocol          = "-1"
  security_group_id = aws_security_group.awsk3s01.id
}