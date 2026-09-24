#!/usr/bin/env bash
# Agent node: fabric gateway + a capability for ledger-read ONLY, handed to OpenShell
# as a provider credential (the agent will only ever see a placeholder).
set -euo pipefail
source "$(dirname "$0")/common.sh"

say "fabric gateway on ${GATEWAY_LISTEN} (capability required on every call)"
pkill -f "gateway proxy --listen ${GATEWAY_LISTEN}" 2>/dev/null || true
nohup "$FABRIC" gateway proxy --listen "$GATEWAY_LISTEN" >/tmp/afr-gw.log 2>&1 &
sleep 2

say "grant: mcp://ledger-read only (default MCP methods: initialize, notifications/initialized, tools/list, tools/call), 30 minutes"
export FABRIC_CAPABILITY="$("$FABRIC" grant mcp://ledger-read --ttl 30m --json \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')"

say "OpenShell provider: the capability lives here, not in the sandbox"
"$OPENSHELL" provider profile import -f "$ROOT/agent-node/openshell/fabric-gateway-profile.yaml" >/dev/null 2>&1 || true
"$OPENSHELL" provider delete fabric >/dev/null 2>&1 || true
"$OPENSHELL" provider create --name fabric --type agent-fabric-gateway --credential FABRIC_CAPABILITY
