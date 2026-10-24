# Cost analysis for the Finance Lead

Estimates use eu-west-1 on-demand prices, 730 hours per month, light lab traffic. Prices change: confirm them in the AWS Pricing Calculator (https://calculator.aws) before quoting, and save the calculator link here.

## What bills by the hour (and why)

The Finance Lead heard correctly. Some network pieces charge for every hour they exist, whether or not traffic flows through them: NAT Gateways, load balancers and public IPv4 addresses. Subnets, route tables, security groups, the Internet Gateway and the S3 gateway endpoint cost nothing.

## Monthly estimate

| Item | Qty | Unit price (approx.) | Monthly (per-az mode) | Monthly (single mode) | Why it is needed |
|---|---|---|---|---|---|
| NAT Gateway, hourly | 2 / 1 | 0.048 USD/h | 70.08 | 35.04 | Outbound-only updates for private servers |
| NAT Gateway, data processed | ~5 GB | 0.048 USD/GB | 0.24 | 0.24 | Low because dnf traffic uses the free S3 endpoint |
| Public IPv4 on NAT (Elastic IPs) | 2 / 1 | 0.005 USD/h | 7.30 | 3.65 | Each NAT needs a public address |
| Application Load Balancer, hourly | 1 | 0.0252 USD/h | 18.40 | 18.40 | Health checks and failover across AZs |
| ALB capacity units (LCU) | ~1 | 0.008 USD/LCU-h | 5.84 | 5.84 | Scales with traffic |
| Public IPv4 on ALB | 2 | 0.005 USD/h | 7.30 | 7.30 | One per AZ node |
| EC2 t3.micro (2 front end + 2 internal) | 4 | ~0.0114 USD/h | 33.29 | 33.29 | Free Tier offsets part of this, see below |
| EBS gp3 8 GB, encrypted | 4 | ~0.088 USD/GB-month | 2.82 | 2.82 | Server disks |
| VPC Flow Logs to CloudWatch | ~1 GB | ~0.57 USD/GB + storage | ~1.00 | ~1.00 | Audit evidence, 14-day retention |
| S3 gateway endpoint | 1 | free | 0.00 | 0.00 | Removes NAT data charges for OS packages |
| Session Manager | n/a | free | 0.00 | 0.00 | Replaces bastion host and keys |
| AWS Budgets | 1 | first 2 budgets free | 0.00 | 0.00 | Alerts the Finance Lead |
| **Total** | | | **~146 USD** | **~107 USD** | |

Running cost is roughly 0.20 USD per hour in per-az mode. Deleting the stack when the lab is not being demonstrated stops almost all of it, and Git sync rebuilds it from the repository.

**Free Tier.** Accounts on the legacy Free Tier get 750 t2.micro or t3.micro hours a month for 12 months, which covers about one of the four servers. Accounts created after 15 July 2025 receive Free Tier credits instead. NAT Gateways and load balancers are not covered either way, so they dominate the bill.

## Where the money goes

About 70 percent of the per-az bill is availability insurance: two NAT Gateways and a load balancer. That is the price of the CTO's requirement that the front end survive an AZ loss and the Head of Operations' requirement that both AZs keep getting updates.

## Choices that lower cost without weakening security

| Choice | Saving |
|---|---|
| S3 gateway endpoint for Amazon Linux repositories | Package downloads skip NAT data charges (0.048 USD/GB) |
| `NatGatewayMode: single` for dev and test | About 39 USD per month per environment. Website stays highly available; only outbound updates lose AZ redundancy |
| Session Manager instead of a bastion host | Saves one always-on server, its public IP and its patching |
| Auto Scaling minimum of 2, maximum of 4 | Pay for peak capacity only on sales days |
| Teardown when idle | Stack deletion is one command; rebuild is one commit |

## Alternatives rejected

| Alternative | Monthly cost | Why rejected |
|---|---|---|
| Single server with a public IP | ~12 USD | Fails the CTO's availability requirement and the Head of Security's exposure requirement |
| Bastion host for admin access | +12 USD and a key to manage | Needs port 22 open and keys shared, which the Head of Security ruled out |
| NAT instance instead of NAT Gateway | ~12 USD each | Cheaper, but another server to patch and a single point of failure; engineering time costs more than the saving |
| Interface endpoints for SSM instead of NAT | ~48 USD (3 endpoints x 2 AZs) | Costs more than one NAT and still does not let servers download from PyPI, Maven or other internet sources |
| Front-end servers in public subnets with public IPs (no ALB) | Saves ~31 USD | No automatic failover, and every server is exposed to the internet |
| CloudFront in front of the ALB | Usage-based | Worth adding for slow mobile connections later; not needed for this week's objectives |

## Recommendation

Run **per-az mode in prod** (~146 USD per month at this size) because an outage on a sales day costs more in lost merchants than a year of the second NAT Gateway. Run **single mode in dev and test** (~107 USD) and delete those stacks when idle. Keep the budget alert active in every environment.
