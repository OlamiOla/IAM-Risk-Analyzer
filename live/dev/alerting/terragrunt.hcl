include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}//modules/alerting"
}

dependency "least_privilege_analysis" {
  config_path = "../least-privilege-analysis"

  mock_outputs = {
    findings_table_stream_arn = "arn:aws:dynamodb:us-east-1:000000000000:table/mock-findings/stream/2026-01-01T00:00:00.000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  findings_table_stream_arn = dependency.least_privilege_analysis.outputs.findings_table_stream_arn
  alert_email_subscribers   = []
  minimum_alert_severity    = "MEDIUM"
}