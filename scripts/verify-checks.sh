#!/usr/bin/env bash
# Runs the client's checks against the deployed stack.
# Usage: ./scripts/verify-checks.sh [stack-name] [region]
set -uo pipefail
STACK="${1:-onward-dev-network}"
REGION="${2:-eu-west-1}"
export AWS_REGION="$REGION"

out() {
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

URL=$(out FrontEndUrl)
ASG=$(out FrontendAutoScalingGroupName)
TG=$(out FrontendTargetGroupArn)
A=$(out InternalServerAId)
B=$(out InternalServerBId)
VPC=$(out VpcId)

echo "== Check 1: front end reachable from the internet =="
for _ in 1 2 3 4 5 6; do
  curl -s --max-time 5 "$URL" | grep -oE 'i-[0-9a-f]{8,}|[a-z]{2}-[a-z]+-[0-9][a-z]' | paste -sd' ' -
done
echo "(responses should come from servers in two Availability Zones)"
aws elbv2 describe-target-health --target-group-arn "$TG" \
  --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output table

echo
echo "== Check 2: no one on the internet can start a connection to an internal server =="
echo "Public IPs on internal servers (expect None):"
aws ec2 describe-instances --instance-ids "$A" "$B" \
  --query "Reservations[].Instances[].[InstanceId,PrivateIpAddress,PublicIpAddress]" --output table
SGS=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" \
  --query 'SecurityGroups[].GroupId' --output text | tr '\t' ',')
echo "Inbound rules open to 0.0.0.0/0 (expect only the ALB group on port 80):"
aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SGS" \
  --query "SecurityGroupRules[?IsEgress==\`false\` && CidrIpv4=='0.0.0.0/0'].[GroupId,FromPort,ToPort]" --output table
echo "Security groups allowing port 22 (expect nothing):"
aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" Name=ip-permission.from-port,Values=22 \
  --query "SecurityGroups[].GroupId" --output text
echo "Private route tables with a route to an internet gateway (expect nothing):"
aws ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC" Name=tag:Name,Values='*private*' \
  --query "RouteTables[].Routes[?GatewayId!=null && starts_with(GatewayId,'igw-')].GatewayId" --output text

echo
echo "== Checks 3 and 4: admin with no open ports, and package downloads =="
echo "Servers registered with Session Manager (expect Online):"
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$A,$B" \
  --query "InstanceInformationList[].[InstanceId,PingStatus,PlatformName]" --output table
CMD=$(aws ssm send-command --instance-ids "$A" "$B" --document-name AWS-RunShellScript \
  --comment "onward lab check: package download" \
  --parameters 'commands=["sudo dnf install -y tree","tree --version","curl -s -o /dev/null -w \"pypi.org HTTP %{http_code}\\n\" https://pypi.org/simple/"]' \
  --query "Command.CommandId" --output text)
sleep 30
for ID in "$A" "$B"; do
  echo "--- $ID ---"
  aws ssm get-command-invocation --command-id "$CMD" --instance-id "$ID" \
    --query "[Status,StandardOutputContent]" --output text | tail -5
done
echo "For an interactive shell: aws ssm start-session --target $A"

echo
echo "== Reference for check 5: front-end servers per AZ =="
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query "AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,HealthStatus]" --output table
