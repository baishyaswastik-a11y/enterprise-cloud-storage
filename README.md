# Enterprise Cloud Storage — Terraform Setup Guide

## Repository structure

```
.
├── .github/
│   └── workflows/
│       └── terraform.yml        ← CI/CD pipeline
├── bootstrap/
│   └── backend.tf               ← Run ONCE to create state backend
├── modules/
│   └── s3-storage/              ← Reusable storage module
├── environments/
│   ├── dev/terraform.tfvars
│   ├── staging/terraform.tfvars
│   └── prod/terraform.tfvars
├── main.tf                      ← Core resources (from previous file)
└── variables.tf                 ← All input definitions
```

---

## First-time setup sequence

### Step 1 — Bootstrap the state backend (run locally, once only)

```bash
cd bootstrap/
terraform init
terraform apply
# Copy the outputs into your GitHub Secrets and backend configs
```

After this, set these in **GitHub → Settings → Secrets and variables → Actions**:

| Secret name          | Value (from bootstrap output)       |
|----------------------|-------------------------------------|
| `AWS_OIDC_ROLE_ARN`  | `github_actions_role_arn` output    |

### Step 2 — Configure backend in each environment

Add this `backend.tf` to each `environments/<env>/` folder:

```hcl
terraform {
  backend "s3" {
    bucket         = "<state_bucket_name from bootstrap>"
    key            = "storage/<env>/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    kms_key_id     = "<kms_key_arn from bootstrap>"
  }
}
```

### Step 3 — Update placeholder values in tfvars

Replace these in each `terraform.tfvars` before applying:

- `allowed_account_ids` — your actual AWS account IDs
- `data_admin_role_arn` — your data team's IAM role ARN
- `cloudwatch_alarm_email` — your on-call email
- `YOUR_ORG/YOUR_REPO` in `terraform.yml` — your GitHub org/repo

### Step 4 — Set up GitHub Environment protection for prod

Go to **GitHub → Settings → Environments → prod**:
- Add required reviewers (e.g. platform-lead, security-team)
- Enable "Required reviewers" — applies blocks must wait for approval

---

## Day-to-day workflow

```
Engineer makes infra change
        ↓
Opens Pull Request
        ↓
CI runs: fmt → validate → tfsec → checkov → plan
        ↓
Plan output posted as PR comment (reviewers see exact diff)
        ↓
Team approves PR
        ↓
Merge to main → Apply job triggers
        ↓ (prod only)
GitHub Environment approval gate — requires manual sign-off
        ↓
terraform apply runs the saved plan (not a fresh plan)
```

---

## State locking — how it works

When any `terraform apply` starts:
1. Writes a lock record to DynamoDB (`LockID = <state file path>`)
2. Applies changes
3. Deletes the lock record

If a second run tries to apply while the lock exists → it blocks with:
```
Error: Error acquiring the state lock
Lock Info: ID=<uuid>, Who=github-actions, Operation=apply
```

No manual intervention needed — the lock auto-releases when apply completes.

---

## Adding a new environment

```bash
mkdir environments/uat
cp environments/staging/terraform.tfvars environments/uat/terraform.tfvars
# Edit uat/terraform.tfvars with uat account details
# Add backend.tf with key = "storage/uat/terraform.tfstate"
```

The same `main.tf` and `variables.tf` serve all environments — no code duplication.
