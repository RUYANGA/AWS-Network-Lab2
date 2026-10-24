# onward-network: Secure network for the Onward Logistics order system

Lab: **Designing Secure Network for Onward Logistics Order System** (Network & Security on AWS, Week 2)
Owner: **Merci RUYANGA** | Region: **eu-west-1** | Stack: **onward-network**

A highly available, private-by-default VPC built entirely with CloudFormation and deployed with CloudFormation Git sync. Merchants and customers reach the order front end through a load balancer that spans two Availability Zones; internal order services have no inbound path from the internet; engineers administer every server through Session Manager with no open ports and no keys.

## Repository layout

```
AWS-Network-Lab2/
├── README.md                          This file
├── .gitignore
├── .github/
│   └── workflows/
│       ├── validate.yml               CI: cfn-lint, blocks inline policies and port 22/3389
│       └── secret-scan.yml            CI: gitleaks, blocks committed credentials
├── docs/
│   ├── discovery.md                   Stage 1 report (commit this FIRST)
│   ├── architecture.md                Mermaid diagram, traffic rules, failure behaviour
│   ├── cost-analysis.md               Monthly cost, rejected alternatives, recommendation
│   ├── decisions.md                   Decision log in business terms
│   └── demo-runbook.md                Commands for each client check in the live review
├── bootstrap/
│   └── gitsync-bootstrap.yaml         One-time: GitHub connection + Git sync role + stack execution role
├── deployments/
│   └── onward-dev-network.yaml        Git sync stack deployment file (parameters and tags)
├── templates/
│   └── onward-network.yaml            The network stack (everything in the VPC)
└── scripts/
    ├── verify-checks.sh               Runs the client's checks against the live stack
    ├── simulate-az-failure.sh         Breaks one front-end server and shows the site stays up
    └── rebuild-gitsync.sh             Rebuilds the stack and reattaches Git sync after role changes
```

## What gets built

| Layer | Resources (all named `onward-dev-*`, all tagged Project/Owner/Environment) |
|---|---|
| Network | VPC 10.20.0.0/16; 6 subnets (public, web, internal x 2 AZs); IGW; NAT Gateway per AZ; route tables; free S3 gateway endpoint |
| Front end | Internet-facing ALB in both AZs; target group with `/health` checks; launch template (AL2023, t3.micro, IMDSv2, encrypted gp3); Auto Scaling group min 2 / max 4 with CPU target tracking |
| Internal | Two order-service servers (one per AZ) on port 8080, private IPs only |
| Security | Chained security groups (internet to ALB:80, ALB to web:80, web to internal:8080), no port 22 anywhere, no key pairs |
| Access | `ServerRole` with AWS managed `AmazonSSMManagedInstanceCore`; `SessionOperatorsPolicy` for engineers, limited by tags |
| Audit and cost | VPC Flow Logs to CloudWatch (14 days); AWS Budgets alert |

No inline IAM policies exist in either template. Every policy is AWS managed or customer managed (`AWS::IAM::ManagedPolicy`).

## Requirement traceability

| Requirement | Where it is met |
|---|---|
| Everything in CloudFormation, nothing in the console | `templates/`, `bootstrap/` (only the GitHub OAuth handshake needs a click, see step 3) |
| Deployed with Git sync from version control | `deployments/onward-dev-network.yaml`, step 4 |
| Highly available | ALB + ASG across 2 AZs, NAT per AZ, cross-zone load balancing |
| Head of Security: nothing internal reachable | Private subnets, no public IPs, SG chain, no IGW route |
| Free Tier Amazon Linux servers | `InstanceType` t3.micro/t2.micro, AL2023 from SSM public parameter |
| Front-end page with full name and lab name, preinstalled | Launch template user data installs nginx and the page on every launch |
| Remote admin without inbound SSH | Session Manager, `ServerRole`, no port 22, no `KeyName` |
| Naming and tags | `onward-<env>-<purpose>` on every resource; Project, Owner, Environment tags; stack tags in the deployment file |
| No inline policies | Managed policies only; enforced in CI |
| Internal servers download updates | NAT Gateway per AZ + S3 endpoint |
| Cost explained | `docs/cost-analysis.md`, `MonthlyBudget` |

## Deploy

### Prerequisites

AWS CLI v2 with the Session Manager plugin, signed in with your own identity (IAM Identity Center or CloudShell, not long-lived access keys). A GitHub account.

### 1. Personalise and commit the discovery report first

Owner name (`Merci RUYANGA`) and `BudgetEmail` (`merci.ruyanga@amalitech.com`) are already set in `docs/discovery.md`, `deployments/onward-dev-network.yaml` and this README.

Repository: https://github.com/RUYANGA/AWS-Network-Lab2

```bash
git init
git add .gitignore docs/discovery.md
git commit -m "docs: add discovery report before any build work"
git branch -M main
git remote add origin https://github.com/RUYANGA/AWS-Network-Lab2.git
git push -u origin main
```

The rest of the work arrives through separate pull requests (network template, Git sync deployment, CI validation, verification scripts, documentation), so each change is reviewed on its own.

The first commit containing only `docs/discovery.md` is what shows the thinking came before the build.

### 2. Deploy the bootstrap stack (once per account)

```bash
aws cloudformation deploy \
  --region eu-west-1 \
  --stack-name onward-dev-gitsync-bootstrap \
  --template-file bootstrap/gitsync-bootstrap.yaml \
  --parameter-overrides Environment=dev OwnerName="Merci RUYANGA" \
  --capabilities CAPABILITY_IAM \
  --tags Project=onward Owner="Merci RUYANGA" Environment=dev

aws cloudformation describe-stacks --region eu-west-1 \
  --stack-name onward-dev-gitsync-bootstrap --query "Stacks[0].Outputs" --output table
```

### 3. Activate the GitHub connection

AWS creates connections in a Pending state and only lets a person complete the GitHub OAuth authorisation in the console. This creates no infrastructure. Open Developer Tools > Settings > Connections, select `onward-dev-github`, choose **Update pending connection** and install the AWS Connector app on your repository only.

### 4. Create the Git sync stack

CloudFormation > Create stack > **Sync from Git**:

| Field | Value |
|---|---|
| Stack name | `onward-network` (must start with `onward-` so the execution role can manage its IAM resources) |
| Deployment file | I am providing my own file in my repository |
| Connection / repository / branch | `onward-dev-github` / `AWS-Network-Lab2` / `main` |
| Deployment file path | `deployments/onward-dev-network.yaml` |
| Git sync IAM role | Existing role: `GitSyncServiceRoleArn` from step 2 |
| Stack permissions (IAM role) | `StackExecutionRoleArn` from step 2 |

The stack takes about 8 to 12 minutes; it completes only after both front-end servers signal that the page is serving. Every later push to `main` that touches the template or deployment file updates the stack.

### 5. Verify

```bash
./scripts/verify-checks.sh onward-network eu-west-1
```

See `docs/demo-runbook.md` for the live review.

## Custom domain and HTTPS (DNS at Hostinger or any provider)

Set `DomainName` in `deployments/onward-dev-network.yaml` (for example `orders.example.com`) and merge to `main`. The stack then requests a free ACM certificate, adds an HTTPS listener on port 443 and redirects HTTP to HTTPS. DNS stays at your provider; you add two records there by hand.

1. Merge the change. The stack update pauses on `FrontendCertificate` (CREATE_IN_PROGRESS) until the certificate is validated. Get the validation record:
   ```bash
   aws acm list-certificates --region eu-west-1 --certificate-statuses PENDING_VALIDATION \
     --query "CertificateSummaryList[].CertificateArn" --output text \
   | xargs -n1 aws acm describe-certificate --region eu-west-1 --certificate-arn \
     --query "Certificate.DomainValidationOptions[].ResourceRecord" --output table
   ```
2. At the DNS provider (Hostinger: Domains > your domain > DNS / Nameservers > Manage DNS records), add a **CNAME** record:
   - Name: the part of the record `Name` before your domain (for example `_3f1a2b...orders`)
   - Target: the record `Value` (ends in `.acm-validations.aws`)
   - Keep it in place: ACM uses it to renew the certificate automatically.
3. Validation usually completes in 5 to 30 minutes and the stack update continues.
4. Point the domain at the load balancer with a second **CNAME** record:
   - Name: the subdomain (for example `orders`)
   - Target: the stack output `LoadBalancerDnsName`
5. Open the `FrontEndUrl` output (`https://<your domain>`).

Use a subdomain such as `orders.example.com`. The root domain (`example.com`) cannot be a CNAME at most providers.

## Give engineers access

Attach the stack output `SessionOperatorsPolicyArn` to the engineers' IAM Identity Center permission set or IAM group from Week 1. It allows `ssm:StartSession` only on instances tagged `Project=onward` and `Environment=dev`. Remove it to revoke access instantly.

## Change, rebuild, tear down

Change: edit the template or deployment file, open a pull request (CI lints it), merge to `main`. For example, set `NatGatewayMode: single` to save about 39 USD per month in dev.

Rebuild: `aws cloudformation delete-stack --stack-name onward-network`, then recreate it with step 4. Nothing outside the repository is needed.

Tear down completely: delete `onward-network` first, then turn off termination protection on `onward-dev-gitsync-bootstrap` and delete it. Never delete the bootstrap while the network stack exists: Git sync and CloudFormation need its roles for every update and delete.

## Handling credentials

No credentials belong in this repository, in pull request comments or in issues. The repository is public, so anything pasted here is exposed immediately.

- Use CloudShell or `aws sso login`; never create long-lived access keys for this lab.
- Before pasting terminal output anywhere, check it for `AKIA`, `ASIA`, `aws_secret_access_key` or `aws_session_token`. Never share the output of `env`, `printenv` or `aws configure export-credentials`.
- The `secret-scan` workflow fails any pull request that commits a credential. Also enable **Settings > Code security > Secret Protection > Push protection** so GitHub rejects such pushes outright.
- If a key leaks: delete the comment or rewrite the commit, revoke active sessions for the IAM role (IAM > Roles > Revoke active sessions), review CloudTrail for the access key ID, close the GitHub alert as revoked, and inform the account owner.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Git sync says the IAM role could not be updated | Every template parameter must have a default; they all do here, so check the deployment file for typos in parameter names |
| `FrontendAutoScalingGroup` times out on create | A server could not reach the internet to install nginx. Check the NAT Gateway and private route tables, then look at `/var/log/cloud-init-output.log` through Session Manager |
| `t3.micro` not Free Tier in your account | Set `InstanceType: t2.micro` in the deployment file |
| Server not shown in Session Manager | Wait 2 to 3 minutes after launch; confirm the instance profile and that outbound 443 works through NAT |
| Execution role denied on an IAM action | The stack name must start with `onward-` |
| Git sync: not authorized to perform `sts:AssumeRole` | The bootstrap roles were replaced. See [Recover Git sync](#recover-git-sync) |

## Recover Git sync

If the stack's Git sync tab shows `CHECK_FOR_SYNC_BLOCKERS_FAILED` with *not authorized to perform: sts:AssumeRole*, the roles Git sync was set up with no longer exist. This happens when `onward-dev-gitsync-bootstrap` is deleted and recreated, because its roles get new names. A stack cannot be pointed at new roles in place, so it is rebuilt from `main`.

1. Redeploy the bootstrap (step 2) and enable termination protection:
   ```bash
   aws cloudformation update-termination-protection --region eu-west-1 \
     --enable-termination-protection --stack-name onward-dev-gitsync-bootstrap
   ```
2. Make sure a GitHub connection is `AVAILABLE`:
   ```bash
   aws codeconnections list-connections --region eu-west-1 \
     --query "Connections[].[ConnectionName,ConnectionStatus,ConnectionArn]" --output table
   ```
   Activate the bootstrap's `onward-dev-github` connection in the console (step 3), or reuse another `AVAILABLE` connection with `CONNECTION_ARN`.
3. Rebuild the stack and reattach Git sync (about 20 to 25 minutes):
   ```bash
   ./scripts/rebuild-gitsync.sh onward-network eu-west-1
   # or: CONNECTION_ARN=arn:aws:codeconnections:... ./scripts/rebuild-gitsync.sh
   ```

The script reads parameters and tags from `deployments/onward-dev-network.yaml`, deletes the stack with the new execution role, recreates it, and points Git sync at the new Git sync role. It is safe to re-run if CloudShell disconnects.
