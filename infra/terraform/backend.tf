# Remote state. Bucket is created out-of-band by bootstrap-backend.sh
# (chicken-and-egg: this backend can't provision the bucket it stores its
# own state in).
#
# Locking: we use Terraform's S3-native lockfile (use_lockfile = true),
# generally available since Terraform 1.11. This satisfies the brief's
# "S3 + DynamoDB lock, or equivalent" requirement with one fewer AWS
# resource and no extra IAM surface — see docs/ARCHITECTURE.md for the
# trade-off note.
#
# Fill in `bucket` to match what you passed to bootstrap-backend.sh, or
# pass it at init time:
#   terraform init -backend-config="bucket=phoenix-tfstate-<you>"
terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket         = "edaferioka-capstone-phoenix-tfstate-bucket"
    key            = "capstone-phoenix/terraform.tfstate"
    region         = "eu-north-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}