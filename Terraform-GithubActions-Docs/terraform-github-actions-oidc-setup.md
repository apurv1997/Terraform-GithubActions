# Setting Up a Terraform + GitHub Actions + OIDC Pipeline on AWS

*A step-by-step log of the groundwork — before a single line of infrastructure code runs.*

This project provisions AWS infrastructure (VPC, subnets, load balancer, EC2, S3) through Terraform, driven entirely by a GitHub Actions pipeline authenticated via OIDC — no long-lived AWS access keys stored anywhere. Before writing any actual infrastructure, four pieces of groundwork have to exist first. Here's what each one is, why it's needed, and the exact commands used.

---

## Step 1: Confirm AWS Access

Nothing else works without an AWS account and sufficient IAM permissions to create VPCs, EC2 instances, load balancers, S3 buckets, and IAM roles. This project uses an AWS account with admin access for setup — though note that the *pipeline's* role (Step 3) is deliberately scoped down, not given admin access.

---

## Step 2: Bootstrap the Remote State Backend

Terraform needs somewhere to store its state file — and that somewhere can't be created *by* Terraform itself, since Terraform needs the backend to already exist before it can use it. So this is a one-time manual setup via the AWS CLI.

**Create the S3 bucket** (bucket names are globally unique across all AWS accounts):

```bash
aws s3api create-bucket \
  --bucket your-unique-bucket-name \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1
```

**Enable versioning** (recover a previous state file if something goes wrong):

```bash
aws s3api put-bucket-versioning \
  --bucket your-unique-bucket-name \
  --versioning-configuration Status=Enabled
```

**Enable default encryption:**

```bash
aws s3api put-bucket-encryption \
  --bucket your-unique-bucket-name \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

**Block all public access** (state files can contain sensitive values):

```bash
aws s3api put-public-access-block \
  --bucket your-unique-bucket-name \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

**Create the DynamoDB lock table** — used to prevent two `terraform apply` runs from colliding:

```bash
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1
```

> **Note:** the partition key must be named exactly `LockID` — that's a hardcoded expectation inside Terraform's S3 backend, not a naming choice. DynamoDB attribute names are case-sensitive, so `LOCKID` or `lockid` won't work.

This is referenced later in `backend.tf` (Step 4).

---

## Step 3: Set Up the GitHub-to-AWS OIDC Trust

Instead of storing long-lived AWS access keys as GitHub secrets, GitHub Actions authenticates into AWS by assuming an IAM role via OpenID Connect (OIDC) — short-lived, scoped credentials, generated fresh on every workflow run.

**a) Create the OIDC identity provider** (once per AWS account):

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

**b) Write the trust policy** — defines *who* is allowed to assume the role. This is scoped to a specific GitHub repo, not the whole account:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Principal": {
                "Federated": "arn:aws:iam::183088117150:oidc-provider/token.actions.githubusercontent.com"
            },
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": [
                        "sts.amazonaws.com"
                    ]
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": [
                        "repo:apurv1997/Terraform-GithubActions:*"
                    ]
                }
            }
        }
    ]
}
```

The `:*` at the end matches any branch, tag, or pull request event from this repo. This can be tightened later — e.g. `repo:apurv1997/Terraform-GithubActions:ref:refs/heads/main` to allow only the `main` branch, or `:pull_request` to allow only PR-triggered runs.

**c) Create the role using that trust policy:**

```bash
aws iam create-role \
  --role-name GitHubAction-AssumeRole \
  --assume-role-policy-document file://trust-policy.json
```

**d) Attach permission policies** — scoped to only what this project needs, not `AdministratorAccess`:

```bash
aws iam attach-role-policy --role-name GitHubAction-AssumeRole --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
aws iam attach-role-policy --role-name GitHubAction-AssumeRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-role-policy --role-name GitHubAction-AssumeRole --policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess
aws iam attach-role-policy --role-name GitHubAction-AssumeRole --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-role-policy --role-name GitHubAction-AssumeRole --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
```

**e) Grab the role ARN** — needed later in the GitHub Actions workflow YAML:

```bash
aws iam get-role --role-name GitHubAction-AssumeRole --query Role.Arn --output text
```

---

## Step 4: Repo and Terraform Skeleton

**a) Clone the repo:**

```bash
git clone https://github.com/apurv1997/Terraform-GithubActions.git
cd Terraform-GithubActions
```

**b) `provider.tf`:**

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}
```

**c) `backend.tf`** — wires up the S3 bucket and DynamoDB table from Step 2:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-unique-bucket-name"
    key            = "vpc-project/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

**d) `variables.tf` and `main.tf`** — left empty for now; filled in once the actual VPC resources are written.

**e) `.gitignore`:**

```
.terraform/
*.tfstate
*.tfstate.*
crash.log
*.tfvars
override.tf
override.tf.json
```

**f) Verify the backend connects, then push:**

```bash
terraform init
git add .
git commit -m "Initial Terraform skeleton with S3 backend"
git push -u origin main
```

A clean `terraform init` (something like *"Successfully configured the backend"*) confirms the S3 bucket and DynamoDB table from Step 2 are wired up correctly.

---

## What's Built So Far — and What Isn't Yet

By the end of Step 4:
- ✅ A place for Terraform to safely store and lock its state (S3 + DynamoDB)
- ✅ A way for GitHub Actions to authenticate into AWS without stored keys (OIDC + IAM role)
- ✅ A repo with the basic Terraform scaffolding wired to that backend

**Not yet built:**
- ❌ The actual infrastructure (VPC, subnets, NAT gateway, ALB, EC2, S3 bucket for logs) — Step 5
- ❌ The GitHub Actions workflow files that make the pipeline actually run — Step 6

Nothing in GitHub Actions triggers until workflow YAML files exist under `.github/workflows/`. Everything above is groundwork the pipeline will depend on — the pipeline itself doesn't exist yet.

*Next: writing and testing the VPC infrastructure locally, before wiring it into the pipeline.*
