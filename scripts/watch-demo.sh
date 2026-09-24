#!/usr/bin/env bash
# 계획 대비 자동 정지 시연: 감시 시작 → 정상 호출 → 공격 → 자동 freeze → 다음 호출 차단.
set -uo pipefail
source "$(dirname "$0")/common.sh"
export FABRIC
log=$(mktemp)
python3 "$ROOT/agent-node/watch/watch.py" > "$log" 2>&1 &
watcher=$!
sleep 2

say "1. 계획 안의 호출 (ledger-read)"
"$ROOT/scripts/sandbox-run.sh" python3 /app/agent.py --probe | head -3

say "2. 심어둔 메모가 시키는 공격"
"$ROOT/scripts/sandbox-run.sh" python3 /app/agent.py --replay-attack | grep -E "공격|거부됨|HTTP 0"

wait "$watcher"
say "3. 감시기 기록"
cat "$log"

say "4. 멈춘 뒤의 호출"
"$ROOT/scripts/sandbox-run.sh" python3 /app/agent.py --probe | tail -1

"$FABRIC" gateway unfreeze --all >/dev/null
rm -f "$log"
