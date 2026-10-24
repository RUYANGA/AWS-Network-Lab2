# Live review runbook

Run everything from a terminal with the AWS CLI v2 and the Session Manager plugin installed, signed in as your own IAM identity (no access keys stored on disk; use `aws sso login` or CloudShell).

```bash
export AWS_REGION=eu-west-1
STACK=onward-dev-network
out() { aws cloudformation describe-stacks --stack-name $STACK --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
URL=$(out FrontEndUrl); A=$(out InternalServerAId); B=$(out InternalServerBId)
```

Or run all checks at once: `./scripts/verify-checks.sh`.

## Check 1: the front end can be reached from the internet, always

```bash
for i in $(seq 1 6); do curl -s $URL | grep -oE 'i-[0-9a-f]{8,}|eu-west-1[a-c]' | paste -sd' ' -; done
```

Open `$URL` in a browser: the page shows your full name and the lab name, plus the server ID and AZ. Refresh to see both AZs answer.

## Check 2: no one on the internet can start a connection to an internal server

Show, in this order:

1. `aws ec2 describe-instances --instance-ids $A $B --query "Reservations[].Instances[].PublicIpAddress"` returns nothing: no public address exists to connect to.
2. The private route tables have no route to the Internet Gateway, only `0.0.0.0/0 -> nat-...`. NAT only carries connections that start inside.
3. `onward-dev-orders-internal-sg` inbound allows only port 8080 from `onward-dev-orders-web-sg`.
4. Try it: `curl --max-time 5 http://<internal private IP>:8080` from your laptop times out (private addresses are not routable on the internet).
5. Optional evidence: in CloudWatch Logs Insights on `/onward/dev/vpc-flow-logs`, filter for records whose destination is an internal server private IP and whose source is a public address; there are none, because the internet has no path to those addresses.

## Check 3: internal servers can download a software package

```bash
aws ssm start-session --target $A
# inside the session:
sudo dnf install -y tree && tree --version
curl -sI https://pypi.org/simple/ | head -1
```

## Check 4: engineers administer each internal server without opening ports

The session in check 3 is the proof. Then show:

```bash
aws ec2 describe-security-groups --filters Name=vpc-id,Values=$(out VpcId) Name=ip-permission.from-port,Values=22
aws ec2 describe-instances --instance-ids $A $B --query "Reservations[].Instances[].KeyName"
```

Both return empty: no port 22 rule and no key pair. Repeat `start-session` for `$B`. Point to `SessionOperatorsPolicyArn` as the only way an engineer gets access.

## Check 5: what happens to the front end if a component goes down

```bash
./scripts/simulate-az-failure.sh
```

Keep the browser open on `$URL` and refresh. Narrate: ALB health checks fail twice (about 20 seconds), traffic moves to the healthy AZ, every request still returns HTTP 200, and the Auto Scaling group launches a replacement that installs the page by itself. Then walk through the failure table in `docs/architecture.md`.

## Check 6: what the design costs and which alternatives were rejected

Walk through `docs/cost-analysis.md`: hourly items, the ~146 vs ~107 USD comparison, the rejected alternatives and the recommendation.

## Check 7: the whole setup can be rebuilt from the repository

```bash
aws cloudformation delete-stack --stack-name $STACK
aws cloudformation wait stack-delete-complete --stack-name $STACK
```

Then recreate the stack with Git sync (README, step 4) or push any commit to `main`, and rerun `./scripts/verify-checks.sh`. Show the Git sync status dashboard and the commit history, with `docs/discovery.md` as the first commit.

## Code walkthrough order

1. `deployments/onward-dev-network.yaml`: how Git sync finds the template and parameters.
2. Parameters and conditions: naming, tags, `NatGatewayMode`.
3. Subnets and route tables: three tiers, two AZs, who has an IGW route.
4. Security groups: the chain ALB to web to internal, no port 22.
5. IAM: `ServerRole` with an AWS managed policy, `SessionOperatorsPolicy`, no inline policies.
6. ALB, launch template user data, Auto Scaling group with `CreationPolicy`.
7. Internal servers, flow logs, budget, outputs.
