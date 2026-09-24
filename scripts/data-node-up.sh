#!/usr/bin/env bash
# Data node: synthetic lender database + two MCP services published on the mesh.
# The database and the MCP servers bind to loopback only; the mesh is the only way in.
set -euo pipefail
source "$(dirname "$0")/common.sh"

say "DB 띄우기 (합성 데이터, postgres:16, 127.0.0.1:${PG_PORT})"
docker rm -f afr-pg >/dev/null 2>&1 || true
docker run -d --name afr-pg -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=fintech \
  -p "127.0.0.1:${PG_PORT}:5432" postgres:16-alpine >/dev/null
until docker exec afr-pg pg_isready -U postgres -q 2>/dev/null; do sleep 1; done; sleep 2
cat "$ROOT/data-node/db/schema.sql" "$ROOT/data-node/db/seed.sql" "$ROOT/data-node/db/scenario.sql" \
  | psql_db -q -v ON_ERROR_STOP=1 >/dev/null
psql_db -At -c "select 'customers='||count(*)||' transactions='||(select count(*) from fintech.transaction) from fintech.customer"

say "MCP 서비스 (read: 집계만 / admin: 원본 내보내기·승인)"
pkill -f "server.py --role (read|admin)" 2>/dev/null || true
cd "$ROOT/data-node/ledger_mcp" && uv sync -q
PGURL="$PGURL" nohup uv run python server.py --role read  --port 8801 >/tmp/afr-read.log  2>&1 &
PGURL="$PGURL" nohup uv run python server.py --role admin --port 8802 >/tmp/afr-admin.log 2>&1 &
sleep 4

say "두 서비스를 사설망에 등록 (공개 포트 없음)"
"$FABRIC" serve http://127.0.0.1:8801 --name ledger-read  --kind mcp
"$FABRIC" serve http://127.0.0.1:8802 --name ledger-admin --kind mcp
