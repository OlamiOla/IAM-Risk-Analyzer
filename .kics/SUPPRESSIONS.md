# KICS Suppressions — iam-risk-analyzer

Documented per project convention. Every suppression must include rationale.

| Module | Rule ID | Rationale | Suppression Syntax |
|---|---|---|---|
| audit-history | (jsonencode false positive, if triggered) | `event_pattern` is an AWS EventBridge pattern schema, not an IAM policy document — jsonencode() is appropriate here and does not create the false-positive pattern KICS flags for IAM policies | `# kics-scan ignore-block` above the `event_pattern` block, if flagged |

_No suppressions applied yet — add entries here as KICS findings are triaged during first pipeline run._