terraform {
  backend "s3" {
    bucket  = "jef-k8slab-tf-remote-state"
    key     = "awsk3s01/us-east-2/terraform.tfstate"
    region  = "us-east-2"
  }
}