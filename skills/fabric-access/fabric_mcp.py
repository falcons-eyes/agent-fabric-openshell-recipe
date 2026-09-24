#!/usr/bin/env python3
"""Agent Fabric 게이트웨이로 MCP 도구 하나를 부른다. 표준 라이브러리만 쓴다.

  python3 fabric_mcp.py <서비스> tools                       # 도구 목록
  python3 fabric_mcp.py <서비스> <도구> '{"인자": "값"}'      # 도구 호출

여권은 환경변수 FABRIC_CAPABILITY(자리표시자)를 그대로 보낸다. 진짜 값은
OpenShell 프록시가 게이트웨이로 가는 요청에만 붙인다.
"""

import json
import os
import sys
import urllib.error
import urllib.request

GATEWAY = os.environ.get("FABRIC_GATEWAY_URL") or "http://host.openshell.internal:17777"
NETWORK = os.environ.get("FABRIC_NETWORK") or "Default"


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    service, tool = sys.argv[1], sys.argv[2]
    args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
    if tool == "tools":
        body = {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
    else:
        body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": tool, "arguments": args}}
    req = urllib.request.Request(
        f"{GATEWAY}/gw/{NETWORK}/{service}/mcp",
        data=json.dumps(body).encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {os.environ.get('FABRIC_CAPABILITY', '')}",
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            out = json.loads(r.read())
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} {e.read().decode(errors='replace')[:300]}")
        return 1
    except urllib.error.URLError as e:
        print(f"연결 실패: {e.reason}")
        return 1
    res = out.get("result", out)
    if tool == "tools":
        for t in res.get("tools", []):
            schema = t.get("inputSchema") or {}
            need = set(schema.get("required", []))
            params = ", ".join(
                f"{k}: {v.get('type', '?')}{'' if k in need else ' (선택)'}"
                for k, v in (schema.get("properties") or {}).items()
            )
            print(f"- {t['name']}({params}): {t.get('description', '')}")
        return 0
    if res.get("structuredContent") is not None:
        print(json.dumps(res["structuredContent"], ensure_ascii=False, indent=1))
    else:
        for c in res.get("content", []):
            print(c.get("text", ""))
    return 1 if res.get("isError") else 0


if __name__ == "__main__":
    sys.exit(main())
