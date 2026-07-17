include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}//modules/least-privilege-analysis"
}

dependency "iam_inventory" {
  config_path = "../iam-inventory"

  mock_outputs = {
    inventory_table_name = "mock-inventory-table"
    inventory_table_arn  = "arn:aws:dynamodb:us-east-1:000000000000:table/mock-inventory-table"
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
  inventory_table_name          = dependency.iam_inventory.outputs.inventory_table_name
  inventory_table_arn           = dependency.iam_inventory.outputs.inventory_table_arn
  kms_key_arn                   = dependency.shared_kms.outputs.kms_key_arn
  unused_access_threshold_days  = 90
  schedule_expression           = "rate(1 day)"
  log_retention_days            = 90
}