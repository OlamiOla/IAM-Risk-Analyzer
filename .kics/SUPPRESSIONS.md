# KICS Suppressions — iam-risk-analyzer

Documented per project convention. Every suppression must include rationale.

| Module | Rule ID | Rationale | Suppression Syntax |
|---|---|---|---|
| audit-history | (jsonencode false positive, if triggered) | `event_pattern` is an AWS EventBridge pattern schema, not an IAM policy document — jsonencode() is appropriate here and does not create the false-positive pattern KICS flags for IAM policies | `# kics-scan ignore-block` above the `event_pattern` block, if flagged |

_No suppressions applied yet — add entries here as KICS findings are triaged during first pipeline run._

| reporting | f861041c-8c9f-4156-acfc-5e6e524f5884 (S3 Bucket Logging Disabled) | `reports_access_logs` is itself the destination access-log bucket for `reports`. Enabling access logging on the log-destination bucket creates a self-referential/infinite logging chain with no security benefit. Public access is blocked and encryption is enforced on this bucket instead. | `# kics-scan ignore-block` above the `aws_s3_bucket.reports_access_logs` resource in `modules/reporting/main.tf`. Note: KICS does not support per-query suppression at block level (see Checkmarx/kics#8015), so ignore-block suppresses all findings on this resource — acceptable here since the resource is minimal and single-purpose. |