# The read-only permission boundary

This is the most important part of the whole agent. The agent is safe not because we
asked it nicely to be safe, but because IAM makes it **physically impossible** for it
to change anything. Even if the model hallucinates a "fix", or a prompt injection tries
to make it act, the IAM boundary rejects any write call.

The agent has read-only glasses, not a wrench.

## Attach these two AWS-managed policies to the auditor identity

Both are maintained by AWS. Together they cover every check the agent runs, with zero
write permissions.

| Policy | ARN | What it gives |
|--------|-----|---------------|
| `SecurityAudit` | `arn:aws:iam::aws:policy/SecurityAudit` | AWS's designated security-auditor job-function policy. Read access to security-relevant configuration across services. |
| `ViewOnlyAccess` | `arn:aws:iam::aws:policy/job-function/ViewOnlyAccess` | Fills the cost-resource gaps: Elastic IPs, volumes, snapshots, load balancers. |

Underneath, both policies are `Get*` / `List*` / `Describe*` only. No `Create`, no
`Delete`, no `Put`, no `Modify`.

## Create a dedicated read-only user (recommended)

```bash
# 1. Create a dedicated identity for the agent
aws iam create-user --user-name aws-auditor

# 2. Attach the two read-only managed policies
aws iam attach-user-policy --user-name aws-auditor \
  --policy-arn arn:aws:iam::aws:policy/SecurityAudit
aws iam attach-user-policy --user-name aws-auditor \
  --policy-arn arn:aws:iam::aws:policy/job-function/ViewOnlyAccess

# 3. Create access keys for the profile the agent uses
aws iam create-access-key --user-name aws-auditor
# then: aws configure --profile aws-auditor   (paste the keys)
```

Point the agent at this profile by setting `AWS_PROFILE` in the agent's `mcpServers`
`env` blocks (see `agent/aws-auditor.json`).

## Prefer a role? Use this trust + attach

```bash
aws iam create-role --role-name aws-auditor \
  --assume-role-policy-document file://trust-policy.json
aws iam attach-role-policy --role-name aws-auditor \
  --policy-arn arn:aws:iam::aws:policy/SecurityAudit
aws iam attach-role-policy --role-name aws-auditor \
  --policy-arn arn:aws:iam::aws:policy/job-function/ViewOnlyAccess
```

`trust-policy.json` in this folder is a starter you can edit for your principal.

## Defense in depth: also restrict the tool

The IAM boundary is the real guardrail. On top of it, the agent config restricts the
`use_aws` tool to a specific list of read services (`toolsSettings.use_aws.allowedServices`).
Two independent walls: the tool can only call a short list of services, and IAM only
permits reads within them.
