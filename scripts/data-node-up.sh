#!/usr/bin/env bash
# Data node: synthetic lender database + two MCP services published on the mesh.
# The database and the MCP servers bind to loopback only; the mesh is the only way in.
set -euo pipefail
source "$(dirname "$0")/common.sh"

say "database (synthetic data, postgres:16 on 127.0.0.1:${PG_PORT})"
docker rm -f afr-pg >/dev/null 2>&1 || true
docker run -d --name afr-pg -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=fintech \
  -p "127.0.0.1:${PG_PORT}:5432" postgres:16-alpine >/dev/null
until pg_isready -h 127.0.0.1 -p "$PG_PORT" -q; do sleep 1; done; sleep 2
psql "$PGURL" -q -v ON_ERROR_STOP=1 -f "$ROOT/data-node/db/schema.sql" -f "$ROOT/data-node/db/seed.sql" \
  -f "$ROOT/data-node/db/scenario.sql" >/dev/null
psql "$PGURL" -At -c "select 'customers='||count(*) from fintech.customer"

say "MCP services (read: aggregates only / admin: raw export + approval)"
cd "$ROOT/data-node/ledger_mcp" && uv sync -q
PGURL="$PGURL" nohup uv run python server.py --role read  --port 8801 >/tmp/afr-read.log  2>&1 &
PGURL="$PGURL" nohup uv run python server.py --role admin --port 8802 >/tmp/afr-admin.log 2>&1 &
sleep 4

say "publish both on the private mesh (no public port)"
"$FABRIC" serve http://127.0.0.1:8801 --name ledger-read  --kind mcp
"$FABRIC" serve http://127.0.0.1:8802 --name ledger-admin --kind mcp
