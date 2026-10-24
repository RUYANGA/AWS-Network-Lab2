# Decision log

Company standard: write down each decision with its reason, in business terms.

| # | Decision | Reason (business terms) | Alternatives considered |
|---|---|---|---|
| D1 | Region eu-west-1 | Lowest latency from West Africa over European cable landings, all needed services, lower prices than the opt-in Cape Town Region | af-south-1, eu-west-2 |
| D2 | Two Availability Zones | Meets the CTO's "keep working if part of the data center fails" at the lowest cost; a third AZ adds cost with little extra benefit at this size | One AZ (fails requirement), three AZs (later, for prod) |
| D3 | Three subnet tiers: public, web, internal | Only the load balancer and NAT face the internet. Separating web and internal limits damage if the website is compromised | Two tiers (web and internal sharing subnets) |
| D4 | Front-end servers in private subnets behind an ALB | Customers reach the site through one stable address that routes around failures; servers themselves are never exposed | Public IPs on servers |
| D5 | Auto Scaling group, min 2, max 4, scale at 60% CPU | Always one server per AZ; handles 3x sales-day volume automatically; only pay for peak when it happens | Fixed four servers |
| D6 | NAT Gateway per AZ by default, `single` as a parameter | Prod keeps updates flowing through an AZ loss; dev and test can save about 39 USD per month | NAT instance, endpoints only |
| D7 | S3 gateway endpoint | Free, and moves OS package downloads off the paid NAT data path | None (no downside) |
| D8 | Session Manager for all admin access, no key pairs, no port 22 | Meets the Head of Security's rule while keeping the Head of Operations' engineers productive; access is per person and revocable | SSH keys, bastion host, EC2 Instance Connect |
| D9 | `SessionOperatorsPolicy` limited to `Project=onward` and the environment tag | Least privilege: an engineer with dev access cannot open a shell on prod | Account-wide `ssm:StartSession` |
| D10 | Security groups reference each other instead of IP ranges | Rules stay correct when servers are replaced or scaled; nothing to update by hand | CIDR-based rules |
| D11 | No inline IAM policies; customer managed or AWS managed only | Policies are reusable, versioned and visible to auditors; enforced in CI | Inline role policies |
| D12 | IMDSv2 required, encrypted disks | Blocks a common credential-theft technique; protects data at rest for data protection rules | Defaults |
| D13 | VPC Flow Logs, 14-day retention | Evidence for the Head of Security and auditors that no inbound internet connection reached internal servers; short retention keeps cost low | No logs, S3 destination |
| D14 | AWS Budgets alert at 80% actual and 100% forecast | The Finance Lead hears about overspend before the invoice | Manual Cost Explorer checks |
| D15 | One template deployed with Git sync; bootstrap roles in a separate template | Every change is a reviewed commit; the environment can be destroyed and rebuilt from Git | Console builds, manual CLI deploys |
| D16 | HTTP only in dev | No domain or certificate exists for the lab; production adds ACM and an HTTPS listener | Self-signed certificate |
| D17 | Front-end page installed by user data at launch | Every new server, including replacements during a failure, serves the page with no human step | Baked AMI (planned once releases move to weekly) |
