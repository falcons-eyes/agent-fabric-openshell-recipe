#!/usr/bin/env bash
# A person on the data node approves a prepared change. This path is local to the data
# node (loopback admin service); no agent capability can reach it.
set -euo pipefail
source "$(dirname "$0")/common.sh"
ID="${1:?approval id}"; WHO="${2:-$(whoami)}"
curl -s -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  http://127.0.0.1:8802/mcp \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"decide\",\"arguments\":{\"approval_id\":${ID},\"approve\":true,\"approver\":\"${WHO}\"}}}"
echo
