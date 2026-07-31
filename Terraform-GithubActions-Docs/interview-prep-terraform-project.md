# Interview Prep — Terraform + GitHub Actions + OIDC AWS Infrastructure Project

Organized basic → intermediate → advanced. Each question has a short talking-point answer, not a full essay — use these as the skeleton, then speak to them in your own words with specifics from what you actually built (bucket names, the OIDC bug, real error messages you saw).

Your single biggest edge in this interview: you didn't just deploy this from a tutorial — you hit and diagnosed **real** failures (OIDC trust mismatch, an IAM permissions gap, a `terraform fmt` failure, a failed git commit). Real debugging stories are worth more than clean deploys. Don't hide them — lead with them when asked "tell me about a challenge."

---

## Opening question you should expect first: "Walk me through what you built"

Have a 60–90 second version ready:

> "I built a VPC-based AWS architecture — public and private subnets across two AZs, a NAT gateway, an application load balancer routing to EC2 instances in the private subnets, and an S3 bucket capturing the ALB's access logs. Everything is provisioned through Terraform, with state stored remotely in S3 with DynamoDB locking. The pipeline itself runs through GitHub Actions — a plan workflow on every pull request, an apply workflow on merge to main — authenticating into AWS via OIDC, so there are no long-lived AWS keys stored anywhere. I also added Checkov for IaC security scanning in CI."

Then let them steer into whichever piece they want to go deeper on.

---

## Basic Level

### AWS Networking
- **What is a VPC?** An isolated, private network you define inside AWS — your own IP address range, subnets, and routing, logically separated from every other customer's traffic.
- **Public vs private subnet — what's the actual difference?** Not the subnet itself — it's the *route table* attached to it. A subnet is "public" only because its route table sends `0.0.0.0/0` traffic to an Internet Gateway. Same subnet with a different route table would be private.
- **What does an Internet Gateway do?** Lets resources with a public IP send and receive traffic directly to/from the internet. Attached at the VPC level, referenced in public route tables.
- **What does a NAT Gateway do, and how is it different from an IGW?** Lets resources in a *private* subnet reach *out* to the internet (e.g., to download packages) without being reachable *from* the internet. One-way, not two-way like an IGW.
- **What's a route table?** A set of rules determining where network traffic from a subnet is directed, based on destination IP range.
- **Security group vs NACL?** Security groups are stateful and attached to resources (instances, ALBs); NACLs are stateless and attached to subnets, evaluated before security groups. This project only uses security groups.

### IAM
- **IAM role vs IAM user?** A user is a persistent identity with long-term credentials, usually for a person. A role is an identity anything can *assume* temporarily — no long-term credentials attached to it directly. This project uses a role exclusively, assumed by GitHub Actions.
- **What is least privilege?** Only grant the exact permissions something needs, nothing more. (Good moment to mention you *didn't* fully follow this at first — attached `IAMFullAccess` to unblock a permission error, then flagged it needs scoping down. Shows self-awareness, not just theory.)

### Terraform
- **What is Infrastructure as Code?** Defining infrastructure in versioned, declarative code instead of manually clicking through a console — reproducible, reviewable, auditable.
- **plan vs apply vs destroy?** `plan` shows what *would* change without changing anything; `apply` executes those changes; `destroy` tears down everything Terraform manages in that state.
- **What is Terraform state?** A file mapping your `.tf` code to the real resources it created — how Terraform knows what already exists.

### Load Balancing & Storage
- **ALB vs NLB vs Classic Load Balancer?** ALB operates at layer 7 (HTTP/HTTPS, path/host-based routing) — used here. NLB operates at layer 4 (TCP/UDP, extreme performance, static IPs). Classic is the legacy predecessor, mostly deprecated now.
- **What is S3, basic use cases?** Object storage — this project uses it for two unrelated purposes: Terraform's remote state, and the ALB's access logs. (Good to be ready to explain that distinction clearly — it's an easy trap to conflate the two.)

---

## Intermediate Level

### Networking
- **Why does the ALB need subnets in at least two AZs?** It's an AWS *requirement*, not a design choice — an ALB won't provision with only one AZ. It's there to survive an entire availability zone going down.
- **Why did you use a single NAT Gateway instead of one per AZ?** Deliberate cost-vs-resilience trade-off for a personal/learning project — one per AZ is the production-grade choice (survives an AZ outage) but roughly doubles the cost. Be ready to say you know the trade-off, not that you didn't think about it.
- **Walk me through what happens when a request hits your ALB.** Request → ALB (in a public subnet) → ALB's listener rule → target group → health-checked EC2 instance in a private subnet → nginx responds → ALB returns it to the client. The instance itself is never directly reachable from the internet.
- **Why put instances in a private subnet at all if the ALB has to reach them anyway?** The ALB can reach them because it's *inside the VPC*, not because it's on the public internet. Only the ALB's public subnet is internet-facing; the instances have no public IP or route to the IGW at all — smaller attack surface.

### IAM / OIDC
- **What is OIDC, and why use it instead of storing AWS access keys as GitHub secrets?** OIDC lets GitHub Actions request a short-lived, cryptographically signed token and exchange it for temporary AWS credentials on each run — no long-lived secret sitting in your repo settings that could leak or need manual rotation.
- **Explain the `sub` and `aud` claims in the trust policy.** `aud` (audience) confirms the token is intended for AWS (`sts.amazonaws.com`). `sub` (subject) identifies *which* GitHub repo/branch/event is allowed to assume the role — this is the actual authorization boundary.
- **Trust policy vs permissions policy on an IAM role — what's the difference?** Trust policy defines *who* can assume the role (the `AssumeRolePolicyDocument`). Permissions policy defines *what* the role can do once assumed. Two completely separate documents, easy to conflate — a great one to be crisp about, since you debugged exactly this distinction firsthand.

### Terraform
- **Why remote state instead of local state?** A GitHub Actions runner is a fresh, disposable machine on every run — it has no memory of previous applies. Remote state (S3) is the one persistent source of truth every run reads from and writes to.
- **What does DynamoDB do here if S3 already stores the state?** State storage and locking are separate problems. DynamoDB prevents two concurrent `apply` runs (e.g., your laptop and a GitHub Actions run at the same moment) from corrupting the state file.
- **What does `terraform plan` actually do internally?** Refreshes its view of real infrastructure (reads current AWS state), compares it against your `.tf` code, and computes a diff — without changing anything.
- **`count` vs `for_each` — which did you use and why?** This project uses `count` for the subnets (simple numeric list of CIDR blocks). `for_each` is generally preferred when the identity of each item matters (e.g., keyed by name) rather than just an index — worth knowing the trade-off even if you used `count` here.

### CI/CD
- **Why separate plan (on PR) from apply (on merge) instead of one workflow?** Separates *proposing* a change from *executing* it — a human reviews the plan output before anything actually touches AWS, the same way code review works for application code.
- **What does `permissions: id-token: write` actually do in the workflow YAML?** Grants the workflow permission to request an OIDC token from GitHub in the first place. Without it, credential configuration fails regardless of how correct the AWS-side trust policy is — a distinction worth being precise about, since it's a genuinely common real-world gotcha.

### Security
- **Explain the security group chaining in your setup.** The ALB's security group allows inbound HTTP from `0.0.0.0/0`. The EC2 instances' security group only allows inbound traffic *from the ALB's security group* — not from any CIDR range. Traffic must pass through the ALB to reach the instances at all.
- **Why IAM role + SSM instead of a bastion host or SSH keys?** No key pairs to manage or lose, no open port 22 anywhere, and access is auditable through IAM/CloudTrail rather than an SSH log. Session Manager tunnels through the AWS API instead of a network path you have to secure separately.

---

## Advanced Level

### Production-readiness thinking
- **What would you change to make this production-grade?** Have 4–5 ready, don't just list — briefly justify each: NAT Gateway per AZ (removes single point of failure), Auto Scaling Group instead of static instances (self-healing, scales with load), HTTPS via ACM + a real domain (currently HTTP only), a WAF in front of the ALB, and splitting Terraform state per environment (dev/staging/prod) instead of one shared state file.
- **How would you structure this for multiple environments (dev/staging/prod)?** Either Terraform workspaces (same code, separate state per workspace) or — more common in real orgs — separate state files/backends per environment with shared modules. Be ready to say which you'd pick and why (separate backends are generally preferred for stronger isolation and independent locking).
- **How would you handle drift — someone manually changing something in the AWS console?** A scheduled workflow running `terraform plan` on a cron trigger, alerting if it detects a difference between code and reality, without auto-applying.

### IAM / security depth
- **Explain GitHub's "immutable subject claims" and why it broke your trust policy.** This is *your* story — tell it directly. GitHub started appending the permanent owner ID and repository ID into the OIDC token's `sub` claim for newly created repos (since April 2026), specifically so a recycled username/repo name can't inherit an old trust relationship. Your original trust policy was written for the older format (`repo:owner/repo:*`), so it silently didn't match. You diagnosed it by printing the actual token's claims rather than re-checking the same static config repeatedly, found the real `sub` value included `@ownerID`/`@repoID`, and updated the trust policy to match — which is also a *more* secure policy than before, since it's pinned to permanent IDs rather than a mutable name.
- **Permissions boundary vs SCP vs resource policy — what's the difference?** A permissions boundary caps the *maximum* permissions an IAM entity can ever have, regardless of what's attached to it. An SCP does something similar but at the AWS Organizations level, across accounts. A resource policy (like your S3 bucket policy) is attached to the *resource* itself, controlling who can access it — different enforcement point than the other two.
- **If this were a real production pipeline, how would you audit or rotate access?** CloudTrail for every `AssumeRoleWithWebIdentity` call (which you actually used mid-project to debug the OIDC issue — mention that), periodic IAM Access Analyzer review of unused permissions, and since OIDC credentials are already short-lived per-run, there's no long-lived secret to "rotate" in the traditional sense — that's part of the architectural benefit.

### Terraform at scale
- **How would you modularize this for reuse?** Break the flat file structure into modules — networking, compute, load-balancing — each with its own variables/outputs, called from a root module per environment. This project deliberately stayed flat for a learning-project scope; know the next step even if you didn't build it.
- **What happens if a state lock gets stuck (e.g., a CI job is killed mid-run)?** `terraform force-unlock <lock-id>` — but be ready to explain the risk: forcing an unlock while something is genuinely still writing can corrupt state, so it should only be used after confirming nothing is actually running.

### DevSecOps
- **Where does IaC scanning (Checkov) fit versus DAST in the security lifecycle?** IaC scanning is "shift-left" — catches misconfigurations before anything is ever deployed, cheapest point to fix. DAST tests a *running* system from the outside, catching things static analysis can't (actual runtime behavior) but much later and more expensively in the cycle.
- **Why run Checkov in `soft_fail` mode initially instead of blocking merges immediately?** Rolling a scanner onto existing infrastructure usually surfaces a backlog of pre-existing findings — blocking immediately would halt all work until every legacy finding is resolved. `soft_fail` reports without blocking, giving room to triage and fix incrementally, then flip to enforcing once the backlog is clear.
- **Not every finding should be "fixed" — explain a case where you deliberately didn't.** Checkov flagged missing deletion protection on the ALB. You didn't enable it, because it would break `terraform destroy` — which conflicts directly with this project's intentional spin-up/tear-down testing cycle. Instead of ignoring it silently, you'd suppress it explicitly with a `checkov:skip` comment stating the reason. This is a strong answer — it shows you don't treat scanner output as gospel, you apply judgment.

---

## "Tell me about a challenge you faced" — your best story

This is worth having fully rehearsed, in STAR format:

- **Situation:** Both the plan and apply GitHub Actions workflows were failing identically at the AWS authentication step, with a generic "not authorized to perform sts:AssumeRoleWithWebIdentity" error.
- **Task:** Figure out why, when every piece of configuration — the OIDC provider, the trust policy, the role ARN in the workflow — looked correct on inspection.
- **Action:** Ruled out causes systematically: confirmed the OIDC provider existed, confirmed the trust policy's structure was valid, confirmed the role ARN matched exactly. Checked CloudTrail for the denied call, which turned out to be a dead end — AWS doesn't log token claims for these failures. Rather than keep re-checking the same static config, added a temporary debug step to the workflow to print the *actual* token GitHub was generating, decoded from its JWT.
- **Result:** Found the real `sub` claim included the repo owner's and repository's permanent AWS-assigned IDs appended to the names — a newer GitHub security feature the original trust policy (written before that rollout) didn't account for. Updated the trust policy to match the real format, which resolved it — and left the project with a trust policy pinned to immutable IDs rather than a mutable name, which is more resilient going forward.

That story demonstrates: systematic elimination over guessing, knowing when a data source (CloudTrail) isn't going to help and pivoting to a better one, and understanding *why* the fix works rather than just copying a Stack Overflow answer.
