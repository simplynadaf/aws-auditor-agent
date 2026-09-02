# AWS Auditor — Your First Read-Only AI Agent

![AWS Audit Agent in 10 minutes using Kiro Crew](assets/thumbnail.png)

A single JSON file and one Markdown checklist that turn Kiro Crew (or Amazon Q
Developer CLI) into an AI agent that audits a live AWS account for **security risks**
and **wasted spend**, then prints a prioritized, cited report.

The important part: the agent **physically cannot change anything**. It runs on a
read-only IAM boundary. Even if the model hallucinates a fix or a prompt injection
tries to make it act, IAM rejects any write call. Read-only glasses, not a wrench.

> This is the companion repo for the video "Build Your First AI Agent." Grab the two
> files, point them at your account, and you have a working auditor in a few minutes.

---

## What it actually produces

Not a mock. This is the real report the agent generated against 5 intentionally
misconfigured demo resources (full copy in
[`example-report/sample-audit-us-east-1.md`](example-report/sample-audit-us-east-1.md)):

```
# AWS Audit — us-east-1, 2026-09-02

## Executive summary
Scoped to the 5 resources tagged demo-auditor=true, this audit found 8 findings:
1 CRITICAL, 3 HIGH, 2 MEDIUM, and 3 cost items. The single most urgent problem is a
publicly readable S3 bucket (demo-auditor-public-5403)...

## Top 3 — do these now
1. Public S3 bucket demo-auditor-public-5403 — bucket policy grants s3:GetObject to *
2. Security group sg-055250cbcc6f3b37b — SSH port 22 open to 0.0.0.0/0
3. GuardDuty is disabled in us-east-1 — no threat detection is running
...
### [COST] Unassociated Elastic IP — ~$3.65/month
- Resource: eipalloc-000992c9956cfaaa5 (public IP 35.173.72.149, no association)
- Estimated impact: $0.005/hr (USE1-PublicIPv4:IdleAddress) x 730 hrs = $3.65/mo
```

Every resource ID, every dollar figure, and every rate above came from a real API call.
The agent's prompt forbids inventing findings, and cost numbers are computed from the
live AWS Price List API.

---

## The anatomy of the agent (what's in the box)

An agent is one JSON file. The six pieces a beginner needs to understand:

| # | Piece | Field | In this agent |
|---|-------|-------|---------------|
| 1 | Identity | `name`, `description` | `aws-auditor` |
| 2 | The brain | `model` | `auto` (CLI picks the model) |
| 3 | Instructions | `prompt` | "read-only, cite only real resources, never invent" |
| 4 | What it can do | `tools` vs `allowedTools` | `fs_read`, `use_aws`, 4 AWS MCP servers |
| 5 | Extra powers | `mcpServers` | security, cloudtrail, pricing, awsdocs |
| 6 | Its knowledge | `resources` | the `aws-audit` skill (the checklist) |

The two most confused fields:

- **`tools`** = what the agent *can* use (the toolbox).
- **`allowedTools`** = what runs *without asking you* (the pre-signed permission slips).

See [`agent/aws-auditor.json`](agent/aws-auditor.json) for the complete, working config.

---

## Repo layout

```
agent/aws-auditor.json          The agent. One file. This is the whole thing.
skill/SKILL.md                  The audit checklist: checks, severities, output format.
iam/README.md                   The read-only permission boundary (the safety story).
iam/trust-policy.json           Starter trust policy if you use a role.
scripts/create-demo-resources.sh    Optional: 5 tagged bad resources to demo against.
scripts/teardown-demo-resources.sh  Removes 100% of them (idempotent, tag-based).
example-report/sample-audit-us-east-1.md   The real report shown above.
```

---

## Quick start

### 1. Set up the read-only IAM identity (do this first)

This is the guardrail. Attach two AWS-managed, read-only policies to a dedicated user
or role. Full instructions in [`iam/README.md`](iam/README.md).

```bash
aws iam create-user --user-name aws-auditor
aws iam attach-user-policy --user-name aws-auditor \
  --policy-arn arn:aws:iam::aws:policy/SecurityAudit
aws iam attach-user-policy --user-name aws-auditor \
  --policy-arn arn:aws:iam::aws:policy/job-function/ViewOnlyAccess
```

Both policies are `Get*` / `List*` / `Describe*` only. No writes exist.

### 2. Install the skill and the agent

```bash
# The checklist (the agent's knowledge)
mkdir -p ~/.kiro/skills/aws-audit
cp skill/SKILL.md ~/.kiro/skills/aws-audit/SKILL.md

# The agent itself
mkdir -p ~/.kiro/agents
cp agent/aws-auditor.json ~/.kiro/agents/aws-auditor.json
```

> Using Amazon Q Developer CLI instead of Kiro Crew? Put the agent in
> `~/.aws/amazonq/cli-agents/` and change the `resources` entry from `skill://` to a
> `file://` path pointing at the checklist. See the notes in `agent/aws-auditor.json`.

### 3. Run it

```bash
# Kiro Crew
kirocrew chat --agent aws-auditor

# Amazon Q Developer CLI
q chat --agent aws-auditor
```

Then ask:

```
Audit us-east-1. Actually call the tools and produce the report.
```

The four AWS MCP servers (`uvx awslabs.*-mcp-server`) are pulled automatically on first
run. They need `uv`/`uvx` installed (`pip install uv`).

---

## Try it safely with demo resources (optional)

Do not want to run it against real infrastructure yet? The scripts create 5 cheap,
clearly tagged, intentionally misconfigured resources so you get a rich report with
nothing real involved.

```bash
bash scripts/create-demo-resources.sh    # creates 5 demo-auditor=* resources
# ... run the audit ...
bash scripts/teardown-demo-resources.sh  # removes 100% of them
```

What it creates (all tagged `demo-auditor=true`, us-east-1, a few cents while alive):

| Resource | Misconfiguration | Findings |
|----------|------------------|----------|
| Public S3 bucket | Public access block off + public read policy | CRITICAL |
| Security group | Inbound 0.0.0.0/0 on port 22 | HIGH |
| EBS volume (gp2, 8 GiB) | Unattached + unencrypted + gp2 | HIGH + 2 COST |
| Elastic IP | Allocated, not associated | COST |
| EBS snapshot | Orphaned | COST |

Teardown deletes by recorded ID, then runs a tag-based sweep as a fallback, then
verifies zero `demo-auditor` resources remain. Idempotent and safe to re-run.

The skill ships **scoped to `demo-auditor=true`** so the demo is repeatable and never
reports anything real. To audit your whole account, delete the "Demo scope" block near
the top of `skill/SKILL.md`. It is one clearly marked block.

---

## Make it yours

The `skill/SKILL.md` file is the part you own. It is a plain checklist:

- Add or remove checks (each row names the read-only API that backs it).
- Change severities to match your risk appetite.
- Edit the report format.
- Delete the demo-scope block to audit everything.

The agent reads this on every run. No code change needed.

---

## What it checks

**Security:** public S3 buckets, root account MFA, security groups open to the world
(22 / 3389 / DB ports), unencrypted EBS/RDS, IAM users without MFA, GuardDuty enabled,
Access Analyzer enabled, Security Hub standards complete, old/unused access keys.

**Cost (each with an estimated $/month from live pricing):** unattached EBS volumes,
unassociated Elastic IPs, orphaned snapshots, gp2 volumes that should be gp3, idle load
balancers.

Findings are mapped to the **Well-Architected Security Pillar** and cited by **CIS AWS
Foundations Benchmark** theme, with a **Trusted Advisor**-style red/yellow/green
severity. It reports passes and honest gaps too. A check that could not run is listed as
"not verified", never implied as a pass.

---

## Requirements

- [Kiro Crew](https://github.com/aws/amazon-q-developer-cli) or Amazon Q Developer CLI
- `uv` / `uvx` for the AWS MCP servers (`pip install uv`)
- AWS credentials with the two read-only policies above
- The demo scripts also need `jq`

---

## License

MIT. See [LICENSE](LICENSE).
