#!/usr/bin/env python3
"""계획 대비 감시: 게이트웨이 원장을 계획과 계속 비교하다가, 벗어나는 순간 freeze.

Cursor Rollouts가 배포 전에 모니터링 계획을 세우고 배포 후 지표를 비교하는 것처럼,
여권을 줄 때 이번 작업의 범위를 plan.json에 적어두고 원장과 맞춰 본다.
규칙 기반이다. 에이전트의 의도를 추론하지 않는다.

  python3 agent-node/watch/watch.py [--plan plan.json] [--interval 1]
"""
import argparse, datetime as dt, json, os, subprocess, sys, time

FABRIC = os.environ.get("FABRIC", "fabric")


def ledger() -> list[dict]:
    out = subprocess.run([FABRIC, "gateway", "ledger", "--json", "--limit", "500"],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out or "[]")


def when(ev: dict) -> dt.datetime:
    return dt.datetime.fromisoformat(ev["at"].replace("Z", "+00:00"))


def check(events: list[dict], plan: dict) -> str | None:
    """계획을 벗어난 첫 이유를 돌려준다. 문제 없으면 None."""
    allowed = plan["허용"]
    refused = sum(1 for e in events if e.get("status", 0) >= 400)
    sent = sum(e.get("bytes_out", 0) for e in events)
    for e in events:
        svc, act = e.get("service", ""), e.get("action", "")
        if svc not in allowed:
            return f"계획에 없는 서비스 {svc} 호출 ({act}, HTTP {e.get('status')})"
        if act not in allowed[svc]:
            return f"{svc}에 계획에 없는 동작 {act}"
    if refused > plan["허용하는_거부_횟수"]:
        return f"거부된 호출 {refused}건 (허용 {plan['허용하는_거부_횟수']}건)"
    if sent > plan["최대_반출_바이트"]:
        return f"반출 {sent}바이트가 한도 {plan['최대_반출_바이트']}바이트 초과"
    return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", default=os.path.join(os.path.dirname(__file__), "plan.json"))
    ap.add_argument("--interval", type=float, default=1.0)
    a = ap.parse_args()
    plan = json.load(open(a.plan, encoding="utf-8"))
    start = dt.datetime.now(dt.timezone.utc)
    print(f"[감시] 시작 · 허용: {', '.join(plan['허용'])} · 반출 한도 {plan['최대_반출_바이트']}B", flush=True)
    seen = 0
    while True:
        events = sorted((e for e in ledger() if when(e) >= start), key=when)
        for e in events[seen:]:
            print(f"[원장] {e['service']:<13} {e['action']:<11} HTTP {e['status']}  반출 {e.get('bytes_out', 0)}B", flush=True)
        seen = len(events)
        reason = check(events, plan)
        if reason:
            subprocess.run([FABRIC, "gateway", "freeze", "--all", "--reason", f"계획 이탈: {reason}"],
                           capture_output=True, text=True, check=True)
            print(f"[정지] 계획 이탈 — {reason}", flush=True)
            print("[정지] 게이트웨이를 멈췄다. 다음 호출부터 모두 403. 해제: fabric gateway unfreeze --all", flush=True)
            sys.exit(2)
        time.sleep(a.interval)


if __name__ == "__main__":
    main()
