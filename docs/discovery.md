# Discovery Report: Designing Secure Network for Onward Logistics Order System

| | |
|---|---|
| Lab | Designing Secure Network for Onward Logistics Order System |
| Name | Merci RUYANGA |
| Date | 22 October 2026 |
| Client | Onward Logistics (see the Client Profile) |

---

## 1. What you found

### The client's need

Onward needs its order website to stay open to merchants and customers through failures and sales-day peaks, while keeping internal order data out of reach of the internet and letting engineers keep working without shared keys.

### Solutions that exist

| Solution | How it works | Trade off for this client |
|---|---|---|
| One server with a public IP (today's model, moved to the cloud) | A single server runs the website and the internal order services and is reachable from the internet. | Strength: cheapest and simplest. Weakness: any fault is a full outage, and the order data sits one exploit away from an attacker. |
| Two public servers behind DNS round robin, admin through a bastion host | DNS hands out two server addresses; engineers SSH through one jump server. | Strength: low cost, some redundancy. Weakness: DNS keeps sending users to a dead server until caches expire, both servers stay exposed, and port 22 and shared keys remain, which the Head of Security has ruled out. |
| Tiered private network with a load balancer across two data centers (Availability Zones) | A load balancer is the only thing facing the internet; it health-checks private web servers in two zones and routes around failures. Internal servers have no public address, reach out for updates through NAT, and engineers log in through Session Manager. | Strength: fails over in seconds, scales for sales days, nothing internal is reachable, no open admin ports. Weakness: load balancer and NAT bill by the hour, roughly 107 to 146 USD per month. |

### What happens with no solution

If the order system stays on one hand-built server, a single fault on a sales day, when volume triples, stops merchants placing orders and customers tracking parcels. Merchants lose sales and some move to a competitor, because reliability is what Onward sells. Even large providers suffer zone-level failures: the 2017 Amazon S3 disruption in us-east-1 took down many websites for about four hours, which is why the design spreads the front end across two zones instead of trusting one. On security, an internet-facing server holding order data invites a breach. In 2019 an attacker used a misconfigured, internet-facing component at Capital One to reach credentials on a server and copy data on about 100 million people; the bank was later fined 80 million USD by US regulators. Shared SSH keys also keep the internal audit finding open, because no incident can be traced to a person. Finally, a hand-built server cannot be rebuilt the same way twice, which blocks faster releases and leaves the Finance Lead with no clear view of cost.

### Sources

- AWS, Summary of the Amazon S3 Service Disruption in the Northern Virginia (US-EAST-1) Region (2017): https://aws.amazon.com/message/41926/
- Capital One, Information on the Capital One cyber incident (2019): https://www.capitalone.com/digital/facts2019/
- AWS Well-Architected Framework, Reliability Pillar: https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html
- AWS, What is AWS Systems Manager Session Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html
- AWS, NAT gateways (Amazon VPC User Guide): https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html
- AWS, Amazon VPC pricing: https://aws.amazon.com/vpc/pricing/

---

## 2. The business value of your solution

### Your chosen approach

I chose the tiered private network across two Availability Zones in eu-west-1 (Ireland), built from one CloudFormation template and deployed from Git. It is the only option that meets all four leaders at once: the CTO's site keeps answering when one zone fails, the Head of Security gets no public address on any internal server and no port 22 anywhere, the Head of Operations' engineers keep shell access and servers keep getting updates, and the Finance Lead gets a known monthly cost with a cheaper single-NAT setting for test environments. The cheaper options either fail the availability requirement or keep open ports and shared keys. Ireland was chosen because traffic from West Africa reaches Europe over submarine cables with low, stable latency, and it is cheaper than the opt-in Cape Town Region; the template can move Region with a parameter change if legal advice requires it.

### Services you will use

| Service | The job it does | Why this service, used this way |
|---|---|---|
| Amazon VPC with public, web and internal subnets | Separates what faces the internet from what does not. | Private subnets have no route in from the internet, so internal servers stay unreachable even if a firewall rule is wrong. |
| Application Load Balancer | The single public entry point; sends traffic only to healthy front-end servers in both zones. | Detects a failed server in about 20 seconds and routes around it, so customers do not notice. |
| EC2 Auto Scaling (t3.micro, Amazon Linux 2023) | Keeps at least one front-end server per zone, replaces failed ones and adds servers when busy. | Handles sales-day peaks automatically; Onward pays for extra servers only when they are needed. |
| NAT Gateway, one per zone | Lets private servers download updates without being reachable from outside. | Outbound only. One per zone means losing a zone does not cut off updates in the other. |
| S3 gateway endpoint | Carries Amazon Linux package downloads privately. | Free, and keeps update traffic off the paid NAT data path. |
| Security groups chained by reference | Internet to load balancer, load balancer to web, web to internal only. | Each tier accepts traffic only from the tier in front of it; rules stay correct as servers are replaced. |
| AWS Systems Manager Session Manager | Gives engineers a shell on any server. | No open ports and no keys; access is tied to each person's IAM identity and can be revoked instantly. |
| IAM roles with managed policies | Give servers and engineers only the permissions they need. | No stored credentials and no inline policies, so every permission is visible to auditors. |
| VPC Flow Logs to CloudWatch Logs | Record every connection attempt in the network. | Evidence for the Head of Security and auditors that nothing from the internet reached internal servers. |
| AWS Budgets | Emails an alert at 80 percent of the monthly budget. | The Finance Lead hears about overspend before the invoice arrives. |
| AWS CloudFormation with Git sync | Builds and updates the whole network from the repository. | Every change is a reviewed commit, and the environment can be deleted and rebuilt identically. |

### Who benefits, and how you will know

| Stakeholder | Benefit | How you would know |
|---|---|---|
| CTO | The order website keeps working when a server or a whole zone fails, and grows on sales days. | With one front-end server deliberately broken, the site keeps returning the page with no failed requests; the Auto Scaling group launches a replacement on its own. |
| Head of Security | Nothing internal can be reached from the internet; no admin ports and no shared keys. | Internal servers have no public IP; no security group allows port 22; no key pairs exist; flow logs show no inbound internet connections to private subnets. |
| Head of Operations | Engineers still log in and servers still install updates. | An engineer opens a Session Manager shell on an internal server and runs a package install successfully. |
| Finance Lead | A clear monthly cost and early warning of overspend. | A cost table of about 146 USD per month (about 107 USD in single-NAT mode), and a budget alert email that fires at 80 percent. |

### Limits and risks of your design

- **No HTTPS in dev.** There is no domain or certificate for the lab, so traffic is plain HTTP. Production needs an ACM certificate and an HTTPS listener.
- **Order services are not load balanced.** Each zone has its own order server; if one fails, it needs a stack update to rebuild. Production should add an internal load balancer and an Auto Scaling group for this tier.
- **No database or data layer.** The design covers the network and servers only. Backups, database failover and data retention are out of scope.
- **Single Region.** A full Region outage would take the site down. Multi-Region failover is possible later but costs much more.
- **No web application firewall or DDoS tuning.** The load balancer is open to the internet on port 80; AWS WAF and Shield Advanced are not included.
- **Cost is fixed even when idle.** NAT Gateways and the load balancer bill by the hour, so idle dev and test stacks must be deleted or switched to single-NAT mode.
- **Data protection rules unconfirmed.** Onward's legal team must confirm that storing customer data in Ireland is allowed in every market before production use.
