include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}//modules/auto-remediation"
}

dependency "least_privilege_analysis" {
  config_path = "../least-privilege-analysis"

  mock_outputs = {
    findings_table_name = "mock-findings-table"
    findings_table_arn  = "arn:aws:dynamodb:us-east-1:000000000000:table/mock-findings-table"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "alerting" {
  config_path = "../alerting"

  mock_outputs = {
    sns_topic_arn = "arn:aws:sns:us-east-1:000000000000:mock-risk-alerts"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "shared_kms" {
  config_path = "../shared-kms"

  mock_outputs = {
    kms_key_arn = "arn:aws:kms:us-east-1:000000000000:key/mock-key-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  findings_table_name      = dependency.least_privilege_analysis.outputs.findings_table_name
  findings_table_arn       = dependency.least_privilege_analysis.outputs.findings_table_arn
  sns_topic_arn            = dependency.alerting.outputs.sns_topic_arn
  kms_key_arn              = dependency.shared_kms.outputs.kms_key_arn
  auto_remediate           = false
  remediable_finding_types = ["stale_access_key"]
  schedule_expression      = "rate(1 day)"
}