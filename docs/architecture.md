# Architecture: onward-dev network

GitHub renders the diagram below. Every box is created by `templates/onward-network.yaml`.

```mermaid
flowchart TB
    users(["Merchants and customers"])
    eng(["Engineers (IAM identity)"])
    git(["GitHub repo, main branch"])

    subgraph aws["AWS account, eu-west-1"]
        cfn["CloudFormation Git sync<br/>stack onward-network"]
        ssm["Systems Manager<br/>Session Manager"]
        cw["CloudWatch Logs<br/>VPC Flow Logs"]
        budget["AWS Budgets<br/>onward-dev-network-budget"]

        subgraph vpc["VPC onward-dev-vpc 10.20.0.0/16"]
            igw["Internet Gateway<br/>onward-dev-igw"]
            s3ep["S3 gateway endpoint<br/>(free, Amazon Linux repos)"]

            subgraph azA["Availability Zone A"]
                subgraph pubA["public-a 10.20.0.0/24"]
                    natA["NAT Gateway nat-a"]
                    albA["ALB node"]
                end
                subgraph webA["web-a 10.20.2.0/24 (private)"]
                    feA["Front-end server<br/>nginx, ASG"]
                end
                subgraph intA["internal-a 10.20.4.0/24 (private)"]
                    beA["Order service A<br/>:8080"]
                end
            end

            subgraph azB["Availability Zone B"]
                subgraph pubB["public-b 10.20.1.0/24"]
                    natB["NAT Gateway nat-b"]
                    albB["ALB node"]
                end
                subgraph webB["web-b 10.20.3.0/24 (private)"]
                    feB["Front-end server<br/>nginx, ASG"]
                end
                subgraph intB["internal-b 10.20.5.0/24 (private)"]
                    beB["Order service B<br/>:8080"]
                end
            end
        end
    end

    users -- "HTTP 80" --> igw --> albA & albB
    albA -- "80, alb-sg to web-sg" --> feA
    albB -- "80" --> feB
    albA -. "cross-zone" .-> feB
    albB -. "cross-zone" .-> feA
    feA -- "8080, web-sg to internal-sg" --> beA
    feB -- "8080" --> beB
    beA & feA -- "outbound 443/80" --> natA --> igw
    beB & feB -- "outbound 443/80" --> natB --> igw
    beA & beB & feA & feB -. "dnf" .-> s3ep
    eng -- "IAM + ssm:StartSession" --> ssm
    ssm -. "agent connects outbound,<br/>no inbound port" .-> beA & beB & feA & feB
    git -- "commit" --> cfn
    vpc -. "all traffic metadata" .-> cw
```

## Traffic rules

| From | To | Port | Allowed by |
|---|---|---|---|
| Internet | ALB | 80 | `onward-dev-orders-alb-sg` ingress 0.0.0.0/0 |
| Internet | ALB | 443 (only when `DomainName` is set; port 80 then redirects to HTTPS) | `onward-dev-orders-alb-sg` ingress 0.0.0.0/0 |
| ALB | Front-end servers | 80 | ALB egress to `web-sg`, `web-sg` ingress from `alb-sg` |
| Front-end servers | Order services | 8080 | `web-sg` egress to `internal-sg`, `internal-sg` ingress from `web-sg` |
| Any server | Internet (updates, SSM, AWS APIs) | 443, 80 outbound | SG egress + private route 0.0.0.0/0 to NAT |
| Internet | Any server | any | Nothing. Servers have no public IP and private subnets have no inbound route |
| Anyone | Port 22 | 22 | Nothing. No rule exists |

## Why engineers can log in with no open port

The SSM Agent on each server opens an outbound HTTPS connection to Systems Manager through the NAT Gateway. When an engineer runs `aws ssm start-session`, Systems Manager checks the engineer's IAM permissions (the `SessionOperatorsPolicy` output), then relays the shell over that existing outbound connection. Nothing ever connects inward to the server.

## What happens when a component fails

| Failure | Effect on users | Recovery |
|---|---|---|
| One front-end server crashes | None noticeable. ALB marks it unhealthy after 2 failed checks (about 20 s) and sends all traffic to the other | ASG launches a replacement automatically |
| A whole AZ is lost | Site stays up on the other AZ's ALB node and server | ASG launches replacements in the healthy AZ until the AZ returns |
| One NAT Gateway (per-az mode) | Only that AZ loses outbound updates; the website is unaffected | AWS replaces the NAT; the other AZ is untouched |
| The NAT Gateway (single mode) | Servers in both AZs lose outbound updates; the website still serves pages | Switch to per-az mode with a one-line Git commit |
| An order-service server | The other AZ's order service keeps running | Rebuild with a stack update (an internal load balancer is the next step for production) |
| A bad template change | Git sync rolls the stack back to the last good state | Revert the commit |
