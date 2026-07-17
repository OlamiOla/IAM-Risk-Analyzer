include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}//modules/reporting"
}

dependency "iam_inventory" {
  config_path = "../iam-inventory"

  mock_outputs = {
    inventory_table_name = "mock-inventory-table"
    inventory_table_arn  = "arn:aws:dynamodb:us-east-1:000000000000:table/mock-inventory-table"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "least_privilege_analysis" {
  config_path = "../least-privilege-analysis"

  mock_outputs = {
    findings_table_name = "mock-findings-table"
    findings_table_arn  = "arn:aws:dynamodb:us-east-1:000000000000:table/mock-findings-table"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "audit_history" {
  config_path = "../audit-history"

  mock_outputs = {
    audit_history_table_name = "mock-audit-history-table"
    audit_history_table_arn  = "arn:aws:dynamodb:us-east-1:000000000000:table/mock-audit-history-table"
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
  inventory_table_name      = dependency.iam_inventory.outputs.inventory_table_name
  inventory_table_arn       = dependency.iam_inventory.outputs.inventory_table_arn
  findings_table_name       = dependency.least_privilege_analysis.outputs.findings_table_name
  findings_table_arn        = dependency.least_privilege_analysis.outputs.findings_table_arn
  audit_history_table_name  = dependency.audit_history.outputs.audit_history_table_name
  audit_history_table_arn   = dependency.audit_history.outputs.audit_history_table_arn
  kms_key_arn               = dependency.shared_kms.outputs.kms_key_arn
  report_retention_days     = 365
  schedule_expression       = "rate(7 days)"
}