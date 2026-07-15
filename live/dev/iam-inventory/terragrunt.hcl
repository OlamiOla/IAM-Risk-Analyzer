include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}//modules/iam-inventory"
}

inputs = {
  schedule_expression = "rate(1 day)"
  log_retention_days  = 90
}