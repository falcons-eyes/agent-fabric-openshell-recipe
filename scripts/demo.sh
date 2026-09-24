#!/usr/bin/env bash
# The three-minute demo: the job gets done, the attacks fail, a person stays in control.
set -euo pipefail
source "$(dirname "$0")/common.sh"
GOAL="${1:-Jiangsu Huaxin 거래처의 최근 90일 위험 신호를 정리하고, 필요하면 한도 조정을 준비해줘.}"
RUN=("$OPENSHELL" sandbox create --from "$ROOT/agent-node/agent" --provider fabric
     --policy "$ROOT/agent-node/openshell/sandbox-policy.yaml"
     --env "FABRIC_GATEWAY_URL=http://host.openshell.internal:${GATEWAY_PORT}"
     --env "FABRIC_NETWORK=${FABRIC_NETWORK}" --env "LLM_BASE_URL=${MODEL_URL}" --env "LLM_MODEL=${MODEL}"
     ${GUARDRAIL_URL:+--env "GUARDRAIL_URL=${GUARDRAIL_URL}" --env "GUARDRAIL_MODEL=${GUARDRAIL_MODEL}"}
     --no-keep --)

say "1. the job: the agent plans, calls the ledger through the gateway, and answers"
"${RUN[@]}" python3 /app/agent.py "$GOAL"

say "2. the attacks the injected memo asks for, performed on purpose"
"${RUN[@]}" python3 /app/agent.py --replay-attack

say "3. what left the data node, as the data node recorded it"
psql_db -c "select at::time(0), executed as tool, risk_tier as tier, rows_out, bytes_out, status
                  from fintech.agent_log where nl_input like 'tool:%' order by log_id desc limit 10"

say "4. what the agent node's gateway recorded (allowed and refused, bytes each way)"
"$FABRIC" gateway ledger --limit 10

say "5. pending approvals (a person decides: scripts/approve.sh <id>)"
psql_db -c "select approval_id, cp_id, action, params, status from fintech.approval order by approval_id desc limit 5"

cat <<'NOTE'

Emergency stop (try it while an agent is running):
  fabric gateway freeze --all --reason "suspicious activity"   # the very next call is refused
  fabric gateway unfreeze --all
NOTE
