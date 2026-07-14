#!/usr/bin/env bash
# infra/terraform/bootstrap-backend.sh
#
# ONE-TIME, RUN MANUALLY. This creates the S3 bucket that Terraform's own
# remote-state backend will use. It can't be created BY the Terraform that
# USES it (chicken-and-egg), so it lives outside infra/terraform/*.tf and is
# run by hand, once, before the first `terraform init`.
#
# We use Terraform's dynamodb table for state locking. Because the table is created by Terraform, we can't use it for locking until after the first `terraform apply`. 
# So we create a separate lock table here, which is used only for the initial `terraform init` and `terraform apply`. 
# After that, the lock table created by Terraform will be used.
# See docs/ARCHITECTURE.md for the rationale.
#
# Usage:
#   ./bootstrap-backend.sh <unique-bucket-name> <aws-region>
#
# Example:
#   ./bootstrap-backend.sh edaferioka-phoenix-tfstate-bucket eu-north-1

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <bucket-name> <aws-region> [lock-table-name]" # optional lock table name
    exit 1
fi

BUCKET_NAME="$1"
REGION="$2"
LOCK_TABLE="${3:-terraform-locks}"

echo "========================================="
echo "Terraform Backend Bootstrap"
echo "========================================="
echo "Bucket:      ${BUCKET_NAME}"
echo "Region:      ${REGION}"
echo "Lock Table:  ${LOCK_TABLE}"
echo ""

echo "==> Checking AWS credentials..."
aws sts get-caller-identity >/dev/null

###########################################
# Create S3 Bucket
###########################################

echo "==> Checking if bucket exists..."

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    echo "Bucket already exists."
else
    echo "Creating S3 bucket..."

    if [ "${REGION}" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "${BUCKET_NAME}" \
            --region "${REGION}"
    else
        aws s3api create-bucket \
            --bucket "${BUCKET_NAME}" \
            --region "${REGION}" \
            --create-bucket-configuration LocationConstraint="${REGION}"
    fi
fi

###########################################
# Enable Versioning
###########################################

echo "==> Enabling bucket versioning..."

aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

###########################################
# Enable Encryption
###########################################

echo "==> Enabling server-side encryption..."

aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{
      "Rules":[
        {
          "ApplyServerSideEncryptionByDefault":{
            "SSEAlgorithm":"AES256"
          }
        }
      ]
    }'

###########################################
# Block Public Access
###########################################

echo "==> Blocking public access..."

aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

###########################################
# Create DynamoDB Lock Table
###########################################

echo "==> Checking DynamoDB lock table..."

if aws dynamodb describe-table \
    --table-name "${LOCK_TABLE}" \
    --region "${REGION}" >/dev/null 2>&1; then

    echo "Lock table already exists."

else

    echo "Creating DynamoDB lock table..."

    aws dynamodb create-table \
        --table-name "${LOCK_TABLE}" \
        --attribute-definitions \
            AttributeName=LockID,AttributeType=S \
        --key-schema \
            AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "${REGION}"

    echo "Waiting for table to become ACTIVE..."

    aws dynamodb wait table-exists \
        --table-name "${LOCK_TABLE}" \
        --region "${REGION}"
fi

###########################################
# Finished
###########################################

echo ""
echo "========================================="
echo "Backend successfully created!"
echo "========================================="
echo ""
echo "Update backend.tf with:"
echo ""
echo "bucket         = \"${BUCKET_NAME}\""
echo "region         = \"${REGION}\""
echo "dynamodb_table = \"${LOCK_TABLE}\""
echo ""
echo "Then run:"
echo ""
echo "terraform init"
echo ""
