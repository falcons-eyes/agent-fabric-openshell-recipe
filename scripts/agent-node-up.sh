#!/usr/bin/env bash
# Agent node: fabric gateway + a capability for ledger-read ONLY, handed to OpenShell
# as a provider credential (the agent will only ever see a placeholder).
set -euo pipefail
source "$(dirname "$0")/common.sh"

say "게이트웨이 시작: ${GATEWAY_LISTEN} (모든 호출에 여권 필요)"
pkill -f "gateway proxy --listen ${GATEWAY_LISTEN}" 2>/dev/null || true
nohup "$FABRIC" gateway proxy --listen "$GATEWAY_LISTEN" >/tmp/afr-gw.log 2>&1 &
sleep 2

say "여권 발급: mcp://ledger-read만, 기본 MCP 메서드 4개, 30분"
export FABRIC_CAPABILITY="$("$FABRIC" grant mcp://ledger-read --ttl 30m --json \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')"

say "OpenShell provider에 여권 보관 (샌드박스 안에는 두지 않음)"
"$OPENSHELL" provider profile import -f "$ROOT/agent-node/openshell/fabric-gateway-profile.yaml" >/dev/null 2>&1 || true
"$OPENSHELL" provider delete fabric >/dev/null 2>&1 || true
"$OPENSHELL" provider create --name fabric --type agent-fabric-gateway --credential FABRIC_CAPABILITY
