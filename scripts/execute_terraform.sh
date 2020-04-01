#!/usr/bin/env sh
source $(dirname "$0")/helpers/shared_secrets.sh
BUCKET="${BUCKET?Please provide a S3 bucket to store state in.}"
AWS_REGION="${AWS_REGION?Please provide an AWS region.}"

set -e
action=$1
shift

terraform init --backend-config="bucket=${BUCKET}" \
  --backend-config="key=terraform" \
  --backend-config="region=$AWS_REGION" && \

terraform $action $*
