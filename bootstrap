# ============================================================
# bootstrap/backend.tf
# Run this ONCE manually before anything else.
# This creates the S3 + DynamoDB that stores all other state.
# After apply, copy the outputs into each environment's
# backend.tf block.
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  # Bootstrap uses LOCAL state — this is intentional.
  # The bootstrap bucket stores its own state locally.
}

provider "aws" {
  region = "ap-south-1"
}

# ──────────────────────────────────────────
# KMS key for state file encryption
# ──────────────────────────────────────────
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform remote state encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# ──────────────────────────────────────────
# S3 Bucket — Remote State Storage
# ──────────────────────────────────────────
resource "aws_s3_bucket" "terraform_state" {
  bucket = "your-org-terraform-state-${data.aws_caller_identity.current.account_id}"

  # Prevent accidental deletion of this bucket
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
    # Every terraform apply creates a new state version —
    # you can roll back to any previous infrastructure state
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.terraform_state.id

  # Keep 90 days of state history, then move old versions to cold storage
  rule {
    id     = "state-version-retention"
    status = "Enabled"
    filter {}
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Bucket policy: deny non-TLS and restrict to this account only
resource "aws_s3_bucket_policy" "state" {
  bucket     = aws_s3_bucket.terraform_state.id
  depends_on = [aws_s3_bucket_public_access_block.state]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid       = "DenyExternalAccounts"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ──────────────────────────────────────────
# DynamoDB Table — State Locking
# Prevents two people (or two CI runs) from
# applying Terraform at the same time
# ──────────────────────────────────────────
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"  # No capacity planning needed
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Enable point-in-time recovery on the lock table itself
  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state.arn
  }

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_caller_identity" "current" {}

# ──────────────────────────────────────────
# OIDC Provider — GitHub Actions auth
# Allows GitHub Actions to assume AWS role
# WITHOUT storing any static credentials
# in GitHub Secrets
# ──────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint (stable, verify at setup time)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions_terraform" {
  name = "github-actions-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Restrict to your org/repo — change this
          "token.actions.githubusercontent.com:sub" = "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }]
  })
}

# Attach required permissions to the GitHub Actions role
resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "terraform-execution-policy"
  role = aws_iam_role.github_actions_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      {
        Sid    = "TerraformStateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem",
          "dynamodb:DeleteItem", "dynamodb:DescribeTable"
        ]
        Resource = aws_dynamodb_table.terraform_lock.arn
      },
      {
        Sid    = "TerraformKMSAccess"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = aws_kms_key.terraform_state.arn
      },
      {
        # S3, KMS, IAM, CloudWatch permissions for the actual infra
        Sid    = "InfrastructureManagement"
        Effect = "Allow"
        Action = [
          "s3:*", "kms:*", "iam:*",
          "cloudwatch:*", "logs:*", "sns:*",
          "dynamodb:DescribeTable"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            # Only allow actions in approved regions
            "aws:RequestedRegion" = ["ap-south-1", "ap-southeast-1"]
          }
        }
      }
    ]
  })
}

# ──────────────────────────────────────────
# OUTPUTS — copy these into each env's
# backend configuration after bootstrap
# ──────────────────────────────────────────
output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.bucket
  description = "Use this in terraform backend config"
}

output "dynamodb_lock_table" {
  value       = aws_dynamodb_table.terraform_lock.name
  description = "Use this in terraform backend config"
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_terraform.arn
  description = "Set this as AWS_OIDC_ROLE_ARN in GitHub Secrets"
}

output "kms_key_arn" {
  value     = aws_kms_key.terraform_state.arn
  sensitive = true
}
