#!/usr/bin/env bash
# Rebuilds the network stack with the current bootstrap roles and reattaches Git sync.
# Use when Git sync fails with "not authorized to perform: sts:AssumeRole", for example
# after the bootstrap stack was deleted and recreated (its roles get new names).
# Usage: ./scripts/rebuild-gitsync.sh [stack-name] [region]
# Optional: CONNECTION_ARN=<arn> to use an existing AVAILABLE connection instead of the
# bootstrap one. Safe to re-run: each step skips work that is already done.
set -euo pipefail
STACK="${1:-onward-network}"
R="${2:-eu-west-1}"
BOOT=onward-dev-gitsync-bootstrap
OWNER=RUYANGA
REPO=AWS-Network-Lab2
DEPLOY_FILE=deployments/onward-dev-network.yaml
cd "$(dirname "$0")/.."

out() { aws cloudformation describe-stacks --region "$R" --stack-name "$BOOT" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
CONN="${CONNECTION_ARN:-$(out ConnectionArn)}"
GITROLE=$(out GitSyncServiceRoleArn)
EXEC=$(out StackExecutionRoleArn)

STATUS=$(aws codeconnections get-connection --region "$R" --connection-arn "$CONN" \
  --query Connection.ConnectionStatus --output text)
if [ "$STATUS" != "AVAILABLE" ]; then
  echo "Connection $CONN is $STATUS. Activate it in the console, or set CONNECTION_ARN to an AVAILABLE one."
  exit 1
fi
echo "Connection: AVAILABLE"

# Read parameters and tags from the deployment file so they never drift from Git sync.
section() {
  awk -v s="$1:" '$0 == s {on=1; next} /^[^ ]/ {on=0} on && NF {
    sub(/[ \t]+#.*/, ""); k=$1; sub(/:$/, "", k); $1=""; sub(/^ +/, ""); gsub(/^"|"$/, "")
    print k "=" $0 }' "$DEPLOY_FILE"
}
mapfile -t PARAMS < <(section parameters)
mapfile -t TAGS < <(section tags)
TEMPLATE=$(awk '/^template-file-path:/ {print $2}' "$DEPLOY_FILE")

echo "== 1/5 Removing old Git sync configuration"
aws codeconnections delete-sync-configuration --region "$R" \
  --sync-type CFN_STACK_SYNC --resource-name "$STACK" 2>/dev/null || echo "   (none found)"

echo "== 2/5 Deleting old stack with the current execution role (5-10 min)"
if aws cloudformation describe-stacks --region "$R" --stack-name "$STACK" >/dev/null 2>&1; then
  aws cloudformation delete-stack --region "$R" --stack-name "$STACK" --role-arn "$EXEC"
  aws cloudformation wait stack-delete-complete --region "$R" --stack-name "$STACK"
  echo "   deleted"
else
  echo "   (stack not present)"
fi

echo "== 3/5 Creating $STACK from $TEMPLATE (10-15 min)"
aws cloudformation deploy --region "$R" --stack-name "$STACK" \
  --template-file "$TEMPLATE" --role-arn "$EXEC" --capabilities CAPABILITY_IAM \
  --parameter-overrides "${PARAMS[@]}" --tags "${TAGS[@]}"

echo "== 4/5 Linking $OWNER/$REPO to the connection"
for id in $(aws codeconnections list-repository-links --region "$R" \
    --query "RepositoryLinks[?RepositoryName=='$REPO' && ConnectionArn!='$CONN'].RepositoryLinkId" --output text); do
  aws codeconnections delete-repository-link --region "$R" --repository-link-id "$id" || true
done
LINK=$(aws codeconnections list-repository-links --region "$R" \
  --query "RepositoryLinks[?RepositoryName=='$REPO' && ConnectionArn=='$CONN'].RepositoryLinkId | [0]" --output text)
if [ -z "$LINK" ] || [ "$LINK" = "None" ]; then
  LINK=$(aws codeconnections create-repository-link --region "$R" --connection-arn "$CONN" \
    --owner-id "$OWNER" --repository-name "$REPO" --query RepositoryLinkInfo.RepositoryLinkId --output text)
fi
echo "   repository link: $LINK"

echo "== 5/5 Turning Git sync back on"
aws codeconnections create-sync-configuration --region "$R" \
  --sync-type CFN_STACK_SYNC --resource-name "$STACK" \
  --repository-link-id "$LINK" --branch main --config-file "$DEPLOY_FILE" \
  --role-arn "$GITROLE" \
  --publish-deployment-status ENABLED --trigger-resource-update-on ANY_CHANGE >/dev/null

echo
echo "Done. Front-end URL:"
aws cloudformation describe-stacks --region "$R" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='FrontEndUrl'].OutputValue" --output text
