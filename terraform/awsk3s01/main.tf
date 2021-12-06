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
  velero_name     = "${local.deployment_name}-velero"
}

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

resource "aws_s3_bucket" "velero" {
  bucket = local.velero_name
  acl    = "private"
}

data "aws_iam_policy_document" "velero" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot"
    ]
    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = [
      "${aws_s3_bucket.velero.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "velero" {
  name   = local.velero_name
  policy = data.aws_iam_policy_document.velero.json
}

resource "aws_iam_user" "velero" {
  name = local.velero_name
}

resource "aws_iam_user_policy_attachment" "velero" {
  user       = aws_iam_user.velero.name
  policy_arn = aws_iam_policy.velero.arn
}

resource "aws_iam_access_key" "velero" {
  user = aws_iam_user.velero.name
}

module "k3s" {
  source = "github.com/yardbirdsax/terraform-k3s-on-ec2?ref=b68ad28e4d2b8b9f245a57aed233ff28fc4d099f"
  providers = {
    aws = aws
  }

  ami_id           = "ami-0149a3b1558828b26"
  assign_public_ip = true
  deployment_name  = local.deployment_name
  iam_role_name    = aws_iam_role.role.name
  instance_type    = "t3.medium"
  security_group_ids = [
    aws_security_group.cluster.id,
    aws_security_group.minecraft_bedrock.id
  ]
  subnet_id = data.aws_subnets.subnets.ids[0]

}
