# Terraform-GithubActions

A learning project that provisions a small AWS web infrastructure with Terraform and deploys it through a GitHub Actions CI/CD pipeline using OIDC (no long-lived AWS keys).

## What this deploys

- **VPC** with public and private subnets across 2 availability zones (`ap-south-1a`, `ap-south-1b`)
- **Internet Gateway** foess, **single NAT Gater public subnet egrway** for private subnet egress
- **Route tables** and associations wiring public subnets to the IGW and private subnets to the NAT
- **Security groups**: ALB SG allows inbound HTTP (80) from the internet; EC2 SG allows inbound HTTP only from the ALB SG
- **Application Load Balancer** (public subnets) with a target group and HTTP listener, health-checked on `/`
- **EC2 instances** (Amazon Linux 2023, one per private subnet) running nginx via user data, registered behind the ALB
- **IAM role + instance profile** attaching `AmazonSSMManagedInstanceCore`, so instances are managed via SSM Session Manager instead of SSH/key pairs
- **S3 bucket** for ALB access logs, with server-side encryption and a bucket policy allowing the ELB log delivery service to write to it
- **Remote state**: S3 backend with DynamoDB table for state locking

## Architecture

```
                         Internet
                            |
                       [Internet GW]
                            |
                  ---------------------
                  |                   |
           Public Subnet A      Public Subnet B
                  |                   |
                 [ALB] ---------------+
                  |
            [NAT Gateway] (in Public Subnet A)
                  |
                  ---------------------
                  |                   |
          Private Subnet A     Private Subnet B
                  |                   |
            [EC2 + nginx]       [EC2 + nginx]
```

ALB access logs are written to a dedicated S3 bucket. EC2 instances have no public IPs and no SSH access; management is via SSM.

## CI/CD (GitHub Actions)

Two workflows, both authenticating to AWS via OIDC (`aws-actions/configure-aws-credentials` assuming an IAM role — no static AWS credentials stored in the repo):

- **`plan.yml`** — runs on every PR targeting `main`. Checks formatting (`terraform fmt -check`), runs `terraform validate`, runs a **Checkov IaC security scan** (`bridgecrewio/checkov-action`, soft-fail so it reports without blocking the PR), runs `terraform plan`, and posts the plan output as a comment on the PR.
- **`apply.yml`** — runs on every push to `main`. Runs `terraform init` and `terraform apply -auto-approve`, then prints the outputs.

- ### IaC scanning (Checkov)

[Checkov](https://www.checkov.io/) scans the Terraform code on every PR for misconfigurations (e.g. unencrypted resources, overly permissive security groups, missing logging) and reports findings directly in the Actions run. It's currently set to `soft_fail: true`, so it surfaces issues without failing the pipeline.

This gives a standard review flow: open a PR → see the plan in the PR comments → merge → infra applies automatically.

## Project structure

| File | Purpose |
|---|---|
| `provider.tf` | Terraform/provider version constraints, AWS provider region |
| `backend.tf` | S3 remote state + DynamoDB locking |
| `variable.tf` | Input variables (CIDR ranges, AZs, instance type, etc.) |
| `vpc.tf` | VPC, subnets, IGW, NAT gateway, route tables |
| `security-group.tf` | ALB and EC2 security groups |
| `compute.tf` | EC2 instances and the nginx user-data bootstrap |
| `alb.tf` | Application Load Balancer, target group, listener |
| `s3.tf` | ALB access log bucket, encryption, bucket policy |
| `iam.tf` | EC2 IAM role/instance profile for SSM |
| `output.tf` | ALB DNS name, VPC ID, instance IDs |
| `.github/workflows/plan.yml` | PR-triggered `terraform plan` |
| `.github/workflows/apply.yml` | Merge-triggered `terraform apply` |

## Outputs

- `alb_dns_name` — public DNS name of the load balancer (visit this to hit nginx)
- `vpc_id` — ID of the created VPC
- `instance_ids` — IDs of the EC2 instances

## Prerequisites

- Terraform >= 1.5.0
- An AWS account with an OIDC identity provider trusting GitHub Actions, and an IAM role (`role-to-assume` in the workflows) with permissions to manage the resources above
- An existing S3 bucket + DynamoDB table for remote state (referenced in `backend.tf`)

## Usage

```bash
terraform init
terraform plan
terraform apply
```

In practice, changes are made via PRs so the plan is reviewed before `apply.yml` runs on merge.

## Design notes

- **Single NAT Gateway** (not one per AZ) — deliberate cost tradeoff for a learning environment; both private subnets share it.
- **No SSH access** — EC2 instances rely on SSM Session Manager for shell access instead of key pairs/open port 22.
- **ALB in front of private instances** — instances are never internet-facing directly; only the ALB is public.
