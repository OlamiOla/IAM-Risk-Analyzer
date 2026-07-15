include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}//modules/audit-history"
}

inputs = {
  audit_history_retention_days = 365
  log_retention_days           = 90
}