#!/usr/bin/env bash
#
# teardown-demo-resources.sh
#
# Removes 100% of the resources created by create-demo-resources.sh.
# Deletes by recorded ID first, then runs a tag-based sweep (demo-auditor=true)
# as a fallback so nothing is ever orphaned, even if .demo-resources.json is lost.
# Idempotent: safe to run more than once.
#
# Usage: bash teardown-demo-resources.sh

set -uo pipefail   # not -e: we want to continue deleting even if one item is already gone

REGION="us-east-1"
STATE_FILE="$(dirname "$0")/.demo-resources.json"
TAG_KEY="demo-auditor"

echo "==> Tearing down demo-auditor resources in ${REGION}"

# ---------------------------------------------------------------------------
# Phase 1: delete by recorded ID (fast, precise)
# ---------------------------------------------------------------------------
if [[ -f "${STATE_FILE}" ]]; then
  REGION="$(jq -r '.region' "${STATE_FILE}")"
  BUCKET="$(jq -r '.bucket' "${STATE_FILE}")"
  SG_ID="$(jq -r '.security_group_id' "${STATE_FILE}")"
  VOL_ID="$(jq -r '.volume_id' "${STATE_FILE}")"
  EIP_ALLOC="$(jq -r '.eip_allocation_id' "${STATE_FILE}")"
  SNAP_ID="$(jq -r '.snapshot_id' "${STATE_FILE}")"

  echo "==> [1] Delete snapshot ${SNAP_ID}"
  aws ec2 delete-snapshot --region "${REGION}" --snapshot-id "${SNAP_ID}" 2>/dev/null || true

  echo "==> [2] Release Elastic IP ${EIP_ALLOC}"
  aws ec2 release-address --region "${REGION}" --allocation-id "${EIP_ALLOC}" 2>/dev/null || true

  echo "==> [3] Delete volume ${VOL_ID}"
  aws ec2 delete-volume --region "${REGION}" --volume-id "${VOL_ID}" 2>/dev/null || true

  echo "==> [4] Delete security group ${SG_ID}"
  aws ec2 delete-security-group --region "${REGION}" --group-id "${SG_ID}" 2>/dev/null || true

  echo "==> [5] Empty + delete bucket ${BUCKET}"
  aws s3 rb "s3://${BUCKET}" --force 2>/dev/null || true

  rm -f "${STATE_FILE}"
else
  echo "    No state file found; relying on tag-based sweep."
fi

# ---------------------------------------------------------------------------
# Phase 2: tag-based sweep (fallback — catches anything the ID pass missed)
# ---------------------------------------------------------------------------
echo "==> Tag-based sweep for ${TAG_KEY}=true"

# Snapshots
for s in $(aws ec2 describe-snapshots --region "${REGION}" --owner-ids self \
    --filters "Name=tag:${TAG_KEY},Values=true" --query 'Snapshots[].SnapshotId' --output text); do
  echo "    sweep snapshot ${s}"; aws ec2 delete-snapshot --region "${REGION}" --snapshot-id "${s}" 2>/dev/null || true
done

# Elastic IPs
for a in $(aws ec2 describe-addresses --region "${REGION}" \
    --filters "Name=tag:${TAG_KEY},Values=true" --query 'Addresses[].AllocationId' --output text); do
  echo "    sweep eip ${a}"; aws ec2 release-address --region "${REGION}" --allocation-id "${a}" 2>/dev/null || true
done

# Volumes
for v in $(aws ec2 describe-volumes --region "${REGION}" \
    --filters "Name=tag:${TAG_KEY},Values=true" --query 'Volumes[].VolumeId' --output text); do
  echo "    sweep volume ${v}"; aws ec2 delete-volume --region "${REGION}" --volume-id "${v}" 2>/dev/null || true
done

# Security groups
for g in $(aws ec2 describe-security-groups --region "${REGION}" \
    --filters "Name=tag:${TAG_KEY},Values=true" --query 'SecurityGroups[].GroupId' --output text); do
  echo "    sweep sg ${g}"; aws ec2 delete-security-group --region "${REGION}" --group-id "${g}" 2>/dev/null || true
done

# S3 buckets (find by tag)
for b in $(aws s3api list-buckets --query 'Buckets[].Name' --output text); do
  case "${b}" in
    demo-auditor-*)
      echo "    sweep bucket ${b}"; aws s3 rb "s3://${b}" --force 2>/dev/null || true ;;
  esac
done

# ---------------------------------------------------------------------------
# Verify nothing remains
# ---------------------------------------------------------------------------
echo "==> Verify: remaining demo-auditor resources"
REMAIN=0
for q in \
  "$(aws ec2 describe-snapshots --region "${REGION}" --owner-ids self --filters "Name=tag:${TAG_KEY},Values=true" --query 'length(Snapshots)' --output text)" \
  "$(aws ec2 describe-addresses --region "${REGION}" --filters "Name=tag:${TAG_KEY},Values=true" --query 'length(Addresses)' --output text)" \
  "$(aws ec2 describe-volumes --region "${REGION}" --filters "Name=tag:${TAG_KEY},Values=true" --query 'length(Volumes)' --output text)" \
  "$(aws ec2 describe-security-groups --region "${REGION}" --filters "Name=tag:${TAG_KEY},Values=true" --query 'length(SecurityGroups)' --output text)" ; do
  REMAIN=$((REMAIN + q))
done
if [[ "${REMAIN}" -eq 0 ]]; then
  echo "    Clean. Zero demo-auditor resources remain."
else
  echo "    WARNING: ${REMAIN} tagged resource(s) still present. Re-run this script."
fi
