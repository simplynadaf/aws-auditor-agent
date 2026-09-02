#!/usr/bin/env bash
#
# create-demo-resources.sh
#
# Creates 5 intentionally-misconfigured, clearly-tagged demo resources so the
# AWS Auditor agent has REAL findings to discover on camera. Every resource is
# named/tagged `demo-auditor=true` so it is unmistakable and easy to tear down.
#
# NOTHING here touches or reads existing account resources. The teardown script
# removes 100% of what this creates.
#
# Cost: a few cents for the hour or two they exist. Delete right after recording.
#
# Usage:  bash create-demo-resources.sh
# Region: us-east-1 (change REGION below if needed)

set -euo pipefail

REGION="us-east-1"
RAND="$(date +%s | tail -c 5)"
STATE_FILE="$(dirname "$0")/.demo-resources.json"
TAG_SPEC_KEY="demo-auditor"
PURPOSE="youtube-aws-auditor-demo"

echo "==> Creating demo-auditor resources in ${REGION} (suffix ${RAND})"

# Helper: standard tag set as EC2 CLI shorthand
ec2_tags() {  # $1 = resource-type, $2 = Name value
  echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=${TAG_SPEC_KEY},Value=true},{Key=Purpose,Value=${PURPOSE}},{Key=DeleteAfter,Value=recording}]"
}

# ---------------------------------------------------------------------------
# 1. Public S3 bucket (public access block DISABLED + public read policy)  [CRITICAL]
# ---------------------------------------------------------------------------
BUCKET="demo-auditor-public-${RAND}"
echo "==> [1/5] S3 public bucket: ${BUCKET}"
aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
aws s3api put-bucket-tagging --bucket "${BUCKET}" \
  --tagging "TagSet=[{Key=${TAG_SPEC_KEY},Value=true},{Key=Purpose,Value=${PURPOSE}}]"
# Turn OFF the public access block so a public policy can take effect
aws s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
  "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
# Public-read bucket policy
aws s3api put-bucket-policy --bucket "${BUCKET}" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Sid\": \"DemoPublicRead\",
    \"Effect\": \"Allow\",
    \"Principal\": \"*\",
    \"Action\": \"s3:GetObject\",
    \"Resource\": \"arn:aws:s3:::${BUCKET}/*\"
  }]
}"
echo "demo file - safe to delete" > /tmp/demo-auditor-file.txt
aws s3 cp /tmp/demo-auditor-file.txt "s3://${BUCKET}/demo.txt" >/dev/null
rm -f /tmp/demo-auditor-file.txt

# ---------------------------------------------------------------------------
# 2. Security group open to the world on port 22 (SSH)  [HIGH]
# ---------------------------------------------------------------------------
echo "==> [2/5] Security group open on 22"
VPC_ID="$(aws ec2 describe-vpcs --region "${REGION}" \
  --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
SG_ID="$(aws ec2 create-security-group --region "${REGION}" \
  --group-name "demo-auditor-open-sg-${RAND}" \
  --description "demo-auditor open SSH sg (safe to delete)" \
  --vpc-id "${VPC_ID}" \
  --tag-specifications "$(ec2_tags security-group demo-auditor-open-sg)" \
  --query 'GroupId' --output text)"
aws ec2 authorize-security-group-ingress --region "${REGION}" \
  --group-id "${SG_ID}" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null

# ---------------------------------------------------------------------------
# 3. EBS volume: gp2, unattached, unencrypted  [MEDIUM + COST + COST]
# ---------------------------------------------------------------------------
echo "==> [3/5] gp2 unattached unencrypted volume"
AZ="${REGION}a"
VOL_ID="$(aws ec2 create-volume --region "${REGION}" \
  --availability-zone "${AZ}" --size 8 --volume-type gp2 --no-encrypted \
  --tag-specifications "$(ec2_tags volume demo-auditor-gp2-vol)" \
  --query 'VolumeId' --output text)"
aws ec2 wait volume-available --region "${REGION}" --volume-ids "${VOL_ID}"

# ---------------------------------------------------------------------------
# 4. Elastic IP allocated but not associated  [COST]
# ---------------------------------------------------------------------------
echo "==> [4/5] Unassociated Elastic IP"
EIP_ALLOC="$(aws ec2 allocate-address --region "${REGION}" --domain vpc \
  --tag-specifications "$(ec2_tags elastic-ip demo-auditor-eip)" \
  --query 'AllocationId' --output text)"

# ---------------------------------------------------------------------------
# 5. Old/orphaned EBS snapshot from the gp2 volume  [COST]
# ---------------------------------------------------------------------------
echo "==> [5/5] Orphaned snapshot"
SNAP_ID="$(aws ec2 create-snapshot --region "${REGION}" \
  --volume-id "${VOL_ID}" --description "demo-auditor old snapshot (safe to delete)" \
  --tag-specifications "$(ec2_tags snapshot demo-auditor-old-snap)" \
  --query 'SnapshotId' --output text)"

# ---------------------------------------------------------------------------
# Record all IDs for a clean, guaranteed teardown
# ---------------------------------------------------------------------------
cat > "${STATE_FILE}" <<EOF
{
  "region": "${REGION}",
  "bucket": "${BUCKET}",
  "security_group_id": "${SG_ID}",
  "volume_id": "${VOL_ID}",
  "eip_allocation_id": "${EIP_ALLOC}",
  "snapshot_id": "${SNAP_ID}"
}
EOF

echo ""
echo "==> Done. Created:"
echo "    S3 bucket        : ${BUCKET} (public)"
echo "    Security group   : ${SG_ID} (0.0.0.0/0:22)"
echo "    EBS volume       : ${VOL_ID} (gp2, unattached, unencrypted)"
echo "    Elastic IP       : ${EIP_ALLOC} (unassociated)"
echo "    Snapshot         : ${SNAP_ID} (orphaned)"
echo "    State written to : ${STATE_FILE}"
echo ""
echo "Run teardown-demo-resources.sh when finished recording."
