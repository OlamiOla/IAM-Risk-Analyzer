include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}//modules/iam-inventory"
}

dependency "shared_kms" {
  config_path = "../shared-kms"

  mock_outputs = {
    kms_key_arn = "arn:aws:kms:us-east-1:000000000000:key/mock-key-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  kms_key_arn         = dependency.shared_kms.outputs.kms_key_arn
  schedule_expression = "rate(1 day)"
  log_retention_days  = 90
}