#!/usr/bin/env bash
# Run one command in a fresh OpenShell sandbox built from agent-node/agent, with the
# fabric provider and the recipe's sandbox policy. Image-build chatter is filtered;
# everything the command itself prints is shown.
#   ./scripts/sandbox-run.sh python3 /app/agent.py --probe
set -uo pipefail
source "$(dirname "$0")/common.sh"
"$OPENSHELL" sandbox create --from "$ROOT/agent-node/agent" --provider fabric \
  --policy "$ROOT/agent-node/openshell/sandbox-policy.yaml" \
  --env "FABRIC_GATEWAY_URL=http://host.openshell.internal:${GATEWAY_PORT}" \
  --env "FABRIC_NETWORK=${FABRIC_NETWORK}" --env "LLM_BASE_URL=${MODEL_URL}" --env "LLM_MODEL=${MODEL}" \
  ${GUARDRAIL_URL:+--env "GUARDRAIL_URL=${GUARDRAIL_URL}" --env "GUARDRAIL_MODEL=${GUARDRAIL_MODEL}"} \
  --no-keep -- "$@" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -v -E \
  '^ *(Step [0-9]|--->|Removed intermediate|Sending build|Successfully|Building image|Context:|Gateway:|\[Warning\]|Built image)|is available in the local|Requesting compute|Sandbox allocated|Pulling image|Image already present|Starting sandbox|Created sandbox|Deleted sandbox|^\s*$'
