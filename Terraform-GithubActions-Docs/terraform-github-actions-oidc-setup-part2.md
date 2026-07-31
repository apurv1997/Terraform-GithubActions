# Terraform + GitHub Actions + OIDC — Part 2: Writing the Infrastructure and Wiring the Pipeline

*Steps 5 and 6, including the two issues that actually broke the pipeline — and how they got diagnosed, not just fixed.*

Part 1 covered the groundwork: the remote state backend (S3 + DynamoDB), the OIDC trust between GitHub and AWS, and the basic repo skeleton. This part covers writing the actual infrastructure and turning on the pipeline itself — plus the real troubleshooting that happened along the way, because it didn't work on the first try.

---

## Step 5: Writing the Infrastructure

The target architecture: a VPC with public and private subnets across two availability zones, an internet gateway, a single NAT gateway, route tables, security groups, EC2 instances behind an application load balancer, and an S3 bucket receiving the load balancer's access logs.

Rather than writing and pushing everything at once, the approach here was deliberately incremental: **write `variables.tf` and `vpc.tf` first, push just those two files along with the pipeline, and confirm the pipeline mechanics work end to end before layering in the rest** (security groups, IAM, compute, ALB, S3). The reasoning: if something breaks, it's much easier to tell whether the problem is in the Terraform code or in the pipeline itself when there's less surface area to search through.

`variables.tf` defined the network layout — VPC CIDR, two availability zones, and CIDR blocks for two public and two private subnets. `vpc.tf` built the VPC, internet gateway, four subnets, a single NAT gateway (a deliberate cost-vs-availability tradeoff for a personal project — one per AZ is more resilient but doubles the cost), and the route tables tying it together.

Everything was tested locally first — `terraform init`, `plan`, and `apply` run by hand — before anything touched CI/CD. That's a sequencing choice worth calling out: debugging Terraform logic and debugging pipeline configuration at the same time is much harder than debugging them one at a time.

---

## Step 6: Wiring Up GitHub Actions

Two workflow files went into `.github/workflows/`:

- **`plan.yml`** — triggered on every pull request. Runs `terraform fmt -check`, `terraform validate`, and `terraform plan`, then posts the plan output as a comment on the PR.
- **`apply.yml`** — triggered on every push to `main`. Runs `terraform apply` using the same OIDC role.

This is where things stopped going smoothly.

### Issue 1: `.github` is a hidden folder

First stumble, minor: running `touch .github/workflows/plan.yml` failed with "No such file or directory" — because the `.github/workflows/` directory didn't exist yet, and `touch` can't create missing parent directories. Fixed with `mkdir -p .github/workflows` first. A related moment of confusion right after: `ls` didn't show the newly created `.github` folder at all — because anything starting with a `.` is hidden by default. `ls -a` (or `ls .github/workflows/` directly) confirmed the files were actually there.

### Issue 2: the real one — `AssumeRoleWithWebIdentity` kept failing

Both workflows failed identically at the "Configure AWS credentials" step:

```
Error: Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

The investigation, in order:
1. Confirmed the OIDC identity provider existed in AWS (`aws iam list-open-id-connect-providers`) — it did.
2. Confirmed the trust policy's `Federated` ARN and `sub` condition looked correct on paper — they did.
3. Confirmed the `role-to-assume` ARN in the workflow YAML matched the role exactly — it did.
4. Checked CloudTrail for the denied `AssumeRoleWithWebIdentity` call — this was a dead end; AWS doesn't log the token's actual claims for OIDC failures (`requestParameters: null`), only which role and provider were involved.

Since everything *looked* correct, the only way forward was to stop trusting assumptions and print the actual token GitHub was generating. A temporary debug step was added to `plan.yml`:

```yaml
- name: Debug OIDC token claims
  run: |
    IDTOKEN=$(curl -sSL -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r '.value')
    echo "$IDTOKEN" | cut -d '.' -f2 | base64 -d 2>/dev/null | jq .
```

This printed the token's real `sub` claim:

```
"sub": "repo:apurv1997@76184941/Terraform-GithubActions@1314158603:pull_request"
```

Compared against the trust policy's expected pattern — `repo:apurv1997/Terraform-GithubActions:*` — the mismatch was obvious once both were side by side: the real token had `@76184941` and `@1314158603` (the owner ID and repository ID) embedded in it, which the trust policy didn't account for at all.

**Root cause:** GitHub rolled out "immutable subject claims" in April 2026. For any repository created after that change, GitHub automatically appends the permanent owner and repository IDs into the `sub` claim — so that if a username or repo name is ever recycled, a new owner can't mint a token that impersonates the old trust relationship. Since this repo was created after that rollout, it got the newer format by default, and most existing Terraform/OIDC tutorials (including the trust policy originally written for this project) predate the change.

**Fix:** update the trust policy to match the real, immutable format:

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
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": [
                        "repo:apurv1997@76184941/Terraform-GithubActions@1314158603:*"
                    ]
                }
            }
        }
    ]
}
```

```bash
aws iam update-assume-role-policy \
  --role-name GitHubAction-AssumeRole \
  --policy-document file://trust-policy.json
```

Worth noting: this isn't just a workaround — it's arguably a *better* trust policy than the original, since it's now pinned to the repo's permanent identity rather than its current name.

### Issue 3: `terraform fmt -check` failing

Once OIDC was fixed, the very next run failed at a different, much simpler step — `terraform fmt -check -recursive` flagged `variable.tf` and `vpc.tf` as not matching Terraform's canonical formatting (spacing, alignment — not logic). Fixed locally with:

```bash
terraform fmt -recursive
```

...which rewrites the files in place, followed by committing and pushing the reformatted files. This is now a standing habit going forward: run `terraform fmt` locally before every commit, rather than letting CI catch it.

### Issue 4: reusing a branch name

One git-specific stumble along the way: after `setup-pipeline` had already been pushed once, running `git checkout -b setup-pipeline` again failed with "fatal: a branch named 'setup-pipeline' already exists" — because the shell was already sitting on that branch, and `-b` tries to *create* a new one. Resolved by just pushing to the already-checked-out branch instead of trying to recreate it. The broader habit that came out of this: always branch off a freshly-pulled `main`, and delete a branch once its PR is merged, rather than reusing branch names across separate pieces of work.

---

## Where Things Stand

By the end of step 6:
- ✅ `variables.tf` and `vpc.tf` — written, tested locally, and passing through the pipeline
- ✅ Both GitHub Actions workflows (`plan.yml`, `apply.yml`) — functioning, authenticating via OIDC
- ✅ The OIDC trust policy — fixed and now using the correct immutable-subject-claim format
- ⏳ Remaining infrastructure files not yet pushed: `security-groups.tf`, `iam.tf`, `compute.tf`, `alb.tf`, `s3.tf` — designed, but intentionally held back until the pipeline mechanics were proven solid

*Next: adding the remaining resource files through the same branch → PR → plan → merge → apply cycle, then running the full loop end to end — including an actual `curl` against the load balancer to confirm the whole architecture works together.*
