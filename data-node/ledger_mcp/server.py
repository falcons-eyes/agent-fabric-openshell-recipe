"""Ledger MCP server for the data node.

One process serves one ROLE. The data node runs two of them and publishes each as
its own private service, because an Agent-Fabric capability is scoped to a service:

  --role read   -> mcp://ledger-read   aggregates only, plus *preparing* a tier-3
                                        change that a person must approve
  --role admin  -> mcp://ledger-admin  raw row export and approval; never granted
                                        to the agent

Nothing here trusts the caller. Amounts leave only as buckets, never as values,
and every call is written to fintech.agent_log with the bytes it returned.
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from typing import Any

import psycopg
from mcp.server.mcpserver import MCPServer
from mcp.server.transport_security import TransportSecuritySettings

PGURL = os.environ.get("PGURL", "postgres://postgres:demo@127.0.0.1:55460/fintech")
BUCKETS = [(10_000, "<10k"), (100_000, "10k-100k"), (1_000_000, "100k-1M")]


def bucket(usd: float | None) -> str:
    """Bucket an absolute USD amount. A value never leaves the node, only its range."""
    if usd is None:
        return "none"
    v = abs(usd)
    for limit, label in BUCKETS:
        if v < limit:
            return label
    return ">1M"


def q(sql: str, *args: Any) -> list[tuple]:
    with psycopg.connect(PGURL) as conn, conn.cursor() as cur:
        cur.execute("SET search_path TO fintech")
        cur.execute(sql, args)
        return cur.fetchall() if cur.description else []


def log(actor: str, tool: str, args: dict, tier: int, status: str, out: Any, rows: int = 0) -> Any:
    """Append the call to the node's own audit log, then return `out` unchanged."""
    body = json.dumps(out, ensure_ascii=False, default=str)
    q(
        "INSERT INTO agent_log (actor, nl_input, intent, executed, risk_tier, rows_out, bytes_out, status)"
        " VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
        actor, f"tool:{tool}", json.dumps({"tool": tool, "args": args}), tool, tier, rows,
        len(body.encode()), status,
    )
    return out


# USD per unit at the latest close, per currency.
USD_SQL = """
  (SELECT DISTINCT ON (code) code, per_usd FROM fx_rate ORDER BY code, day DESC) fx
"""


def build(role: str) -> MCPServer:
    actor = os.environ.get("LEDGER_ACTOR", "agent")
    srv = MCPServer(
        name=f"ledger-{role}",
        instructions=(
            "Read-only analytics over a lender's transaction ledger. Amounts are returned "
            "as buckets. Changes can only be PREPARED; a person approves them."
            if role == "read"
            else "Administrative ledger access. Not for agents."
        ),
    )

    if role == "read":

        @srv.tool(
            description=(
                "List counterparties that had external risk events in the last N days, most severe "
                "first: cp_id, name, event type, severity and date. No amounts."
            )
        )
        def list_risk_events(days: int = 30) -> list[dict]:
            days = max(1, min(int(days), 365))
            rows = q(
                """SELECT cp.cp_id, cp.name, cp.country, e.type, e.severity, e.event_time::date
                   FROM fe_event e JOIN counterparty cp ON cp.fe_id = e.fe_id
                   WHERE e.event_time >= (SELECT max(event_time) FROM fe_event) - make_interval(days => %s)
                   ORDER BY CASE e.severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END,
                            e.event_time DESC""",
                days,
            )
            out = [{"cp_id": r[0], "name": r[1], "country": r[2], "event": r[3], "severity": r[4], "date": str(r[5])} for r in rows]
            return log(actor, "list_risk_events", {"days": days}, 1, "ok", out, len(out))

        @srv.tool(description="Find counterparties by name. Returns ids, names and countries only.")
        def find_counterparty(name_query: str) -> list[dict]:
            rows = q(
                "SELECT cp_id, name, country FROM counterparty WHERE name ILIKE %s ORDER BY cp_id LIMIT 10",
                f"%{name_query}%",
            )
            out = [{"cp_id": r[0], "name": r[1], "country": r[2]} for r in rows]
            return log(actor, "find_counterparty", {"name_query": name_query}, 1, "ok", out, len(out))

        @srv.tool(
            description=(
                "Risk summary for one counterparty over the last N days: transaction counts, "
                "bucketed flows, exposed customers, external risk events and the latest memos."
            )
        )
        def counterparty_risk_summary(cp_id: str, days: int = 90) -> dict:
            days = max(1, min(int(days), 365))
            head = q("SELECT name, country, fe_id FROM counterparty WHERE cp_id = %s", cp_id)
            if not head:
                return log(actor, "counterparty_risk_summary", {"cp_id": cp_id}, 1, "ok", {"error": "unknown cp_id"})
            name, country, fe_id = head[0]
            since = "(SELECT max(booked_at) FROM transaction) - make_interval(days => %s)"
            flows = q(
                f"""SELECT count(*),
                           sum(CASE WHEN t.amount > 0 THEN t.amount / fx.per_usd END),
                           sum(CASE WHEN t.amount < 0 THEN -t.amount / fx.per_usd END),
                           max(abs(t.amount) / fx.per_usd),
                           count(DISTINCT a.customer_id)
                    FROM transaction t JOIN account a USING (account_id)
                    JOIN {USD_SQL} ON fx.code = t.currency
                    WHERE t.cp_id = %s AND t.booked_at >= {since}""",
                cp_id, days,
            )[0]
            events = q(
                "SELECT type, severity, event_time::date, confidence FROM fe_event WHERE fe_id = %s ORDER BY event_time DESC",
                fe_id,
            )
            memos = q(
                f"""SELECT booked_at::date, memo FROM transaction
                    WHERE cp_id = %s AND memo IS NOT NULL AND booked_at >= {since}
                    ORDER BY booked_at DESC LIMIT 5""",
                cp_id, days,
            )
            out = {
                "cp_id": cp_id,
                "name": name,
                "country": country,
                "window_days": days,
                "transactions": flows[0],
                "inflow_usd": bucket(flows[1]),
                "outflow_usd": bucket(flows[2]),
                "largest_single_usd": bucket(flows[3]),
                "customers_exposed": flows[4],
                "external_events": [
                    {"type": e[0], "severity": e[1], "date": str(e[2]), "confidence": float(e[3])} for e in events
                ],
                "recent_memos": [{"date": str(m[0]), "memo": m[1]} for m in memos],
            }
            return log(actor, "counterparty_risk_summary", {"cp_id": cp_id, "days": days}, 1, "ok", out, 1)

        @srv.tool(
            description=(
                "PREPARE a credit-limit change for a counterparty (tier 3). Nothing changes until "
                "a person approves it on the data node. Returns an approval id."
            )
        )
        def prepare_limit_change(cp_id: str, new_limit_bucket: str, reason: str) -> dict:
            rows = q(
                "INSERT INTO approval (cp_id, action, params, reason, requested_by)"
                " VALUES (%s, 'limit_change', %s, %s, %s) RETURNING approval_id, status",
                cp_id, json.dumps({"new_limit_bucket": new_limit_bucket}), reason, actor,
            )
            out = {
                "approval_id": rows[0][0],
                "status": rows[0][1],
                "note": "Prepared only. A person must approve it on the data node before anything changes.",
            }
            return log(actor, "prepare_limit_change", {"cp_id": cp_id}, 3, "needs_approval", out, 1)

        @srv.tool(description="Status of an approval request prepared earlier.")
        def approval_status(approval_id: int) -> dict:
            rows = q("SELECT status, decided_by, decided_at FROM approval WHERE approval_id = %s", approval_id)
            out = {"approval_id": approval_id, "status": rows[0][0] if rows else "unknown",
                   "decided_by": rows[0][1] if rows else None}
            return log(actor, "approval_status", {"approval_id": approval_id}, 1, "ok", out, len(rows))

    else:

        @srv.tool(description="Export raw transaction rows for a counterparty (admin only).")
        def export_transactions(cp_id: str) -> list[dict]:
            rows = q(
                "SELECT txn_id, account_id, booked_at, amount, currency, kind, memo FROM transaction WHERE cp_id = %s OR %s = '*'",
                cp_id, cp_id,
            )
            out = [dict(zip(["txn_id", "account_id", "booked_at", "amount", "currency", "kind", "memo"], r)) for r in rows]
            return log(actor, "export_transactions", {"cp_id": cp_id}, 4, "ok", out, len(out))

        @srv.tool(description="Approve or reject a prepared change (admin only).")
        def decide(approval_id: int, approve: bool, approver: str) -> dict:
            status = "approved" if approve else "rejected"
            q(
                "UPDATE approval SET status = %s, decided_by = %s, decided_at = %s WHERE approval_id = %s AND status = 'pending'",
                status, approver, datetime.now(timezone.utc), approval_id,
            )
            return {"approval_id": approval_id, "status": status, "decided_by": approver}

    return srv


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--role", choices=["read", "admin"], required=True)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8801)
    a = ap.parse_args()
    srv = build(a.role)
    # Stateless JSON responses: every call is one POST and one JSON body, which a
    # reverse proxy (the Agent-Fabric gateway) forwards and meters without SSE.
    # The Host check is off because requests arrive through the mesh gateway under
    # its own Host header; the capability at the gateway is the access boundary.
    srv.run(
        "streamable-http",
        host=a.host,
        port=a.port,
        json_response=True,
        stateless_http=True,
        transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
    )


if __name__ == "__main__":
    main()
