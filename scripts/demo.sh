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

say "1. 일: 에이전트가 계획하고, 게이트웨이를 거쳐 원장을 조회하고, 답한다"
"${RUN[@]}" python3 /app/agent.py "$GOAL"

say "2. 공격: 심어 둔 메모가 시키는 일을 그대로 실행"
"${RUN[@]}" python3 /app/agent.py --replay-attack

say "3. 데이터 노드가 남긴 기록"
psql_db -c "select at::time(0), executed as tool, risk_tier as tier, rows_out, bytes_out, status
                  from fintech.agent_log where nl_input like 'tool:%' order by log_id desc limit 10"

say "4. 게이트웨이 원장 (허용·거부, 오간 바이트)"
"$FABRIC" gateway ledger --limit 10

say "5. 승인 대기 (사람이 결정: scripts/approve.sh <번호>)"
psql_db -c "select approval_id, cp_id, action, params, status from fintech.approval order by approval_id desc limit 5"

cat <<'NOTE'

긴급 정지 (에이전트가 도는 중에 해 보기):
  fabric gateway freeze --all --reason "suspicious activity"   # the very next call is refused
  fabric gateway unfreeze --all
NOTE
