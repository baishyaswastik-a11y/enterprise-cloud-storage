# ============================================================
# environments/staging/terraform.tfvars
# Production-mirror: CRR on, longer WORM, full observability
# ============================================================

environment         = "staging"
project_name        = "enterprise-data"
primary_region      = "ap-south-1"
dr_region           = "ap-southeast-1"

# Staging mirrors prod — CRR enabled to catch replication issues pre-prod
enable_cross_region_replication = true

# 90 days — enough to cover most QA cycles and audit requirements
worm_retention_days = 90

intelligent_tiering_archive_days      = 90
intelligent_tiering_deep_archive_days = 180

allowed_account_ids = ["444455556666"]  # Staging AWS account

data_admin_role_arn = "arn:aws:iam::444455556666:role/staging-data-admin"

cloudwatch_alarm_email = "staging-alerts@yourorg.com"

tags = {
  CostCenter = "engineering"
}
