#!/usr/bin/env bash
# Simulates losing the front-end server in one Availability Zone while the
# site stays up. The ALB stops routing to the failed server after about 20 s
# (2 failed health checks x 10 s) and the Auto Scaling group replaces it.
# Usage: ./scripts/simulate-az-failure.sh [stack-name] [region]
set -euo pipefail
STACK="${1:-onward-network}"
REGION="${2:-eu-west-1}"
export AWS_REGION="$REGION"

out() {
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
ASG=$(out FrontendAutoScalingGroupName)
URL=$(out FrontEndUrl)

read -r IID AZ < <(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query "AutoScalingGroups[0].Instances[0].[InstanceId,AvailabilityZone]" --output text)

echo "Breaking $IID in $AZ (stopping its web server)..."
aws ssm send-command --instance-ids "$IID" --document-name AWS-RunShellScript \
  --parameters 'commands=["sudo systemctl stop nginx"]' --comment "AZ failure drill" >/dev/null

echo "Polling the front end for 90 seconds. It should keep answering:"
for _ in $(seq 1 18); do
  CODE=$(curl -s -o /tmp/onward.html -w "%{http_code}" --max-time 5 "$URL" || echo 000)
  SERVED=$(grep -oE 'i-[0-9a-f]{8,}' /tmp/onward.html | head -1 || true)
  echo "$(date +%T)  HTTP $CODE  served by ${SERVED:-?}"
  sleep 5
done

echo "Group members now (a replacement should be launching in $AZ):"
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query "AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,HealthStatus,LifecycleState]" --output table
