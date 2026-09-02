# AWS Audit — us-east-1, 2026-09-02

## Executive summary
Scoped to the 5 resources tagged `demo-auditor=true`, this audit found 8 findings: 1 CRITICAL, 3 HIGH, 2 MEDIUM, and 3 cost items. The single most urgent problem is a publicly readable S3 bucket (`demo-auditor-public-5403`) that lets anyone on the internet download its objects. Total estimated waste from the cost findings is about $4.60/month, small in absolute terms but pure waste from resources attached to nothing.

## Top 3 — do these now
1. Public S3 bucket `demo-auditor-public-5403` — its bucket policy grants `s3:GetObject` to everyone (`Principal: *`). Enable S3 Public Access Block and remove the public policy statement.
2. Security group `sg-055250cbcc6f3b37b` — SSH port 22 is open to `0.0.0.0/0`. Restrict the ingress rule to a known admin IP or use SSM Session Manager instead.
3. GuardDuty is disabled in us-east-1 — no threat detection is running. Enable a GuardDuty detector in the region.

## Security findings

### [CRITICAL] Public S3 bucket readable by anyone
- Resource: `demo-auditor-public-5403`
- Why it matters: Anyone on the internet can read the objects in this bucket. The bucket policy statement `DemoPublicRead` allows `s3:GetObject` on `arn:aws:s3:::demo-auditor-public-5403/*` with `Principal: *`, and `GetBucketPolicyStatus` returns `IsPublic: true`. The Public Access Block is fully off (`BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy`, `RestrictPublicBuckets` all `false`).
- Framework: Well-Architected — Data Protection; CIS: S3 — no public read access.
- Fix (do not run this yourself): In the S3 console, enable Block Public Access for this bucket, then delete the `DemoPublicRead` statement from the bucket policy.

### [HIGH] Security group open to the internet on SSH (port 22)
- Resource: `sg-055250cbcc6f3b37b` (name `demo-auditor-open-sg-5403`, vpc `vpc-66e7371b`)
- Why it matters: A door left open to the whole internet. Ingress allows TCP 22 from `0.0.0.0/0`, exposing SSH to brute-force and scanning from any source.
- Framework: Well-Architected — Infrastructure Protection; CIS: networking — no unrestricted ingress to remote admin ports.
- Fix (do not run this yourself): Replace the `0.0.0.0/0` rule on port 22 with a specific admin CIDR, or remove it and use SSM Session Manager.

### [HIGH] Unencrypted EBS volume
- Resource: `vol-0c85bd44ef6f9c19d` (name `demo-auditor-gp2-vol`, 8 GiB, gp2, us-east-1a)
- Why it matters: The disk is stored unencrypted (`Encrypted: false`). Data at rest has no protection if the underlying storage is accessed.
- Framework: Well-Architected — Data Protection; CIS: EBS — encryption at rest.
- Fix (do not run this yourself): Create an encrypted snapshot/copy and restore to a new encrypted volume, then replace the unencrypted one. Note: this volume is also flagged under Cost below (it is unattached).

### [MEDIUM] IAM Access Analyzer disabled
- Resource: Account 175662053988, region us-east-1 (`list-analyzers` returned an empty list)
- Why it matters: Nothing watches for resources shared externally (buckets, roles, keys). External access such as the public bucket above would not be surfaced by an analyzer.
- Framework: Well-Architected — Detection; CIS: monitoring — external access analysis.
- Fix (do not run this yourself): Create an account or organization Access Analyzer in us-east-1.

### [MEDIUM] Security Hub standards incomplete
- Resource: Account 175662053988, region us-east-1. Both `cis-aws-foundations-benchmark/v/1.2.0` and `aws-foundational-security-best-practices/v/1.0.0` show `StandardsStatus: INCOMPLETE` with reason `NO_AVAILABLE_CONFIGURATION_RECORDER`.
- Why it matters: The dashboard is on, but the checks are off. Without an AWS Config configuration recorder, most Security Hub controls cannot evaluate, so the standards report no meaningful results.
- Framework: Well-Architected — Detection; CIS: monitoring — enabled and complete benchmark.
- Fix (do not run this yourself): Enable an AWS Config configuration recorder in us-east-1 so the subscribed standards can run their controls.

## Cost findings

### [COST] Unattached EBS volume — ~$0.80/month
- Resource: `vol-0c85bd44ef6f9c19d` (8 GiB, gp2, `State: available`, `Attachments: []`)
- Why: Paying for a disk attached to nothing.
- Estimated impact: ~$0.80/month. Calculation: 8 GiB × $0.10/GB-mo (gp2 rate, `EBS:VolumeUsage.gp2`, us-east-1) = $0.80/mo. Assumption: 8 GiB gp2 in us-east-1, on-demand.
- Fix: If the data is not needed, delete the volume (snapshot first if in doubt).

### [COST] Unassociated Elastic IP — ~$3.65/month
- Resource: `eipalloc-000992c9956cfaaa5` (public IP `35.173.72.149`, no association/instance)
- Why: A reserved IP sitting idle, billed hourly.
- Estimated impact: ~$3.65/month. Calculation: $0.005/hr (`USE1-PublicIPv4:IdleAddress`, us-east-1) × 730 hrs = $3.65/mo. Assumption: idle for a full month, on-demand.
- Fix: Release the Elastic IP if it is not needed, or associate it with a running resource.

### [COST] Orphaned / unneeded EBS snapshot — ~$0.40/month
- Resource: `snap-0e8e4ff717cead51e` (8 GiB, of `vol-0c85bd44ef6f9c19d`, description "demo-auditor old snapshot (safe to delete)")
- Why: A backup you likely no longer need.
- Estimated impact: ~$0.40/month. Calculation: 8 GiB × $0.05/GB-mo (`EBS:SnapshotUsage`, us-east-1) = $0.40/mo. Assumption: full 8 GiB billed (`FullSnapshotSizeInBytes` reported as 0, so this is an upper bound based on `VolumeSize`); actual snapshot billing is on used blocks and may be lower.
- Fix: Delete the snapshot if it is no longer required.

### [COST] gp2 volume that should be gp3 — ~$0.16/month savings
- Resource: `vol-0c85bd44ef6f9c19d` (8 GiB, gp2)
- Why: Switch to gp3 for about 20% cheaper storage at equal or better performance. (This volume is currently unattached; the recommended action is to delete it. If it were kept and reattached, gp3 would be the cheaper type.)
- Estimated impact: ~$0.16/month savings. Calculation: 8 GiB × ($0.10 gp2 − $0.08 gp3) = $0.16/mo. Assumption: 8 GiB, us-east-1, on-demand, base gp3 IOPS/throughput sufficient.
- Fix: Prefer deleting the unattached volume; if retained and used, migrate it to gp3.

Total estimated monthly waste (excluding the gp2→gp3 delta, since the volume itself is already counted as deletable): ~$4.85/month.

## Passing checks
- Root account MFA is enabled — `iam:GetAccountSummary` returned `AccountMFAEnabled: 1`. The master key has a lock (PASS).
- Security group `sg-055250cbcc6f3b37b` egress is standard all-traffic to `0.0.0.0/0` (normal default; the inbound rule is the finding, not egress).

## Gaps (not verified)
- IAM users without MFA and old/unused access keys: NOT verified for the demo. The account has 9 IAM users (`GetAccountSummary`), but individual users are not tagged `demo-auditor=true`, so per-user MFA (`iam:ListMFADevices`) and access-key age (`iam:GetAccessKeyLastUsed`) checks were intentionally not run under the demo scope. This is a scope limitation, not a pass.
- RDS encryption: NOT verified. No RDS instance carried the `demo-auditor=true` tag, so `rds:DescribeDBInstances` was not evaluated for this scope.
- Idle load balancer: NOT verified. No ELB/ALB carried the `demo-auditor=true` tag, so `elbv2:DescribeLoadBalancers` and target health were not evaluated for this scope.
- Snapshot true billed size: `FullSnapshotSizeInBytes` reported as 0, so the $0.40/month snapshot estimate uses the 8 GiB `VolumeSize` as an upper bound; actual cost may be lower.

Every resource ID, rate, and number above traces to actual tool output from this run. All pricing is from the AWS Price List API for us-east-1. This audit was read-only; I recommend the fixes but did not and cannot apply them.

