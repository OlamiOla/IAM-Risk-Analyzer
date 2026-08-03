# IAM Risk Analyzer

Automated detection, alerting, auditing, and (optional) remediation of high-risk IAM configurations across an AWS account.

## Overview

This project continuously scans IAM users, roles, and groups to identify:
- Over-permissioned policies (wildcard/high-risk actions)
- Unused access (via IAM Access Analyzer's unused-access findings)
- Stale/inactive access keys
- Historical IAM change activity, for auditing

Findings trigger real-time SNS alerts with remediation guidance. Select finding types (currently: stale access keys) can be auto-remediated on a scheduled basis, gated behind an explicit `auto_remediate` flag — disabled by default.

## Architecture

| Module | Responsibility |
|---|---|
| `iam-inventory` | Scheduled scan of all IAM users, roles, groups, policies, and access keys → DynamoDB |
| `least-privilege-analysis` | Cross-references inventory against IAM Access Analyzer + custom checks (stale keys, wildcard policies) → writes findings to DynamoDB |
| `audit-history` | EventBridge + CloudTrail → logs historical IAM changes to DynamoDB (TTL-based retention) |
| `alerting` | DynamoDB Streams → SNS notifications with remediation steps, filtered by severity |
| `auto-remediation` | Scheduled scan of OPEN findings eligible for automated action (dry-run by default) |
| `reporting` | Weekly aggregate JSON summary report → S3 |

**Dependency flow:**
## Tech Stack

- **IaC**: Terraform + Terragrunt (three-file root split: `account.hcl`, `region.hcl`, `backend.hcl`, `root.hcl`)
- **Compute**: AWS Lambda (Python 3.12)
- **Storage**: DynamoDB (inventory, findings, audit history), S3 (reports)
- **Detection**: IAM Access Analyzer (unused-access + custom logic)
- **Notification**: SNS
- **Scheduling**: EventBridge (scheduled rules + event pattern rules)
- **CI/CD**: GitHub Actions, OIDC authentication (no long-lived credentials)
- **Security scanning**: KICS (Docker image, digest-pinned)

## Prerequisites

- AWS account with the shared backend already provisioned:
  - S3 state bucket: `dev-sec-git-repo-s3`
  - DynamoDB lock table: `dev-terraform-lock-config`
  - OIDC role: `github-actions-portfolio-deploy`
- Terraform >= 1.9.5
- Terragrunt >= 0.68.4

## Deployment

Plan and apply run exclusively through CI/CD (GitHub Actions) — see `.github/workflows/`:
- `kics-scan.yml` — runs on every PR touching `modules/` or `live/`
- `terragrunt-plan.yml` — runs on every PR
- `terragrunt-apply.yml` — runs on merge to `main`, gated behind a required-reviewer approval on the `development` GitHub Environment

Manual local deployment (not recommended outside of initial testing):
```bash
cd live/dev/<module-name>
terragrunt init
terragrunt plan
terragrunt apply
```


## Troubleshooting

**`terragrunt run --all ... -- <command>` fails with "flag not defined" or "Terraform has no command named run"**

This project pins Terragrunt `0.68.4`, which predates the CLI redesign introduced in 0.77+/1.x. The two syntaxes are not interchangeable:

| Terragrunt version | Command form | Flag form |
|---|---|---|
| `< 0.77` (this project) | `terragrunt run-all <command>` | `--terragrunt-non-interactive`, `--terragrunt-parallelism N` |
| `>= 1.0` | `terragrunt run --all --non-interactive --parallelism N -- <command>` | flags before `--`, unprefixed |

If you see either error above, check that `TERRAGRUNT_VERSION` in the workflow env matches the command syntax actually used in that same workflow file — a version bump without a matching syntax update (or vice versa) is the most common cause. The `terragrunt --version` line in the "Setup Terragrunt" step prints what's actually installed in the CI log, which is the fastest way to confirm which syntax applies.

**`terragrunt plan`/`init` fails with "detected no outputs" on a `dependency` block**

This happens when a downstream module's `dependency` block doesn't include the command being run in `mock_outputs_allowed_terraform_commands`. Mocked outputs are only accepted for the commands explicitly listed there — `init` must be included alongside `validate`/`plan`, or `terragrunt run-all init` will fail on any module with a not-yet-applied dependency.

### Branch-scoped CI triggers

`terragrunt-plan.yml` runs on push to `riskanalyzer` (the active feature branch) and on PRs into `main`, giving fast plan feedback while iterating pre-merge. `terragrunt-apply.yml` only ever triggers on push to `main` — feature branch pushes never reach apply, regardless of what the OIDC trust policy allows.

The `github-actions-portfolio-deploy` role's trust policy (`sts:AssumeRoleWithWebIdentity` condition) must list every branch that `plan.yml` runs against, or CI fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity`. Currently allowed `sub` patterns:
- `repo:OlamiOla/IAM-Risk-Analyzer:ref:refs/heads/main`
- `repo:OlamiOla/IAM-Risk-Analyzer:ref:refs/heads/riskanalyzer`
- `repo:OlamiOla/IAM-Risk-Analyzer:pull_request`

**Remove the `riskanalyzer` entry** (both from the trust policy and from `plan.yml`'s `on: push: branches:`) once that branch is merged into `main` and no longer in active use — stale branch trust left on an IAM role is unnecessary drift.


## Configuration

Key tunables per environment, set in each module's `live/dev/<module>/terragrunt.hcl`:

| Variable | Module | Default | Notes |
|---|---|---|---|
| `auto_remediate` | auto-remediation | `false` | Must be explicitly set `true` to perform live remediation |
| `minimum_alert_severity` | alerting | `MEDIUM` | `LOW` \| `MEDIUM` \| `HIGH` |
| `unused_access_threshold_days` | least-privilege-analysis | `90` | Days of inactivity before flagging |
| `alert_email_subscribers` | alerting | `[]` | Set per environment; not hardcoded in module |

## Security Notes

- All IAM policies written as heredoc JSON (not `jsonencode()`) to avoid KICS false positives.
- Every Lambda IAM role is scoped to only the specific resources it touches — no wildcard resource ARNs on write actions.
- `auto-remediation` is limited to reversible, low-risk actions only (disabling stale access keys); no automated deletes.
- KICS suppressions, if any, are documented with rationale in `.kics/SUPPRESSIONS.md`.

## Author

Ola ([@OlamiOla](https://github.com/OlamiOla))

