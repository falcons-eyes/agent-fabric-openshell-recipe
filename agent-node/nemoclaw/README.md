# NemoClaw(OpenClaw)에 붙이기

NVIDIA NemoClaw가 띄운 OpenClaw 에이전트도 같은 방식으로 막는다. 샌드박스 밖으로 나가는 길은 OpenShell 정책이, 사내 서비스로 가는 길은 Agent Fabric 게이트웨이가 쥔다.

> **TL;DR**
> - preset 하나(`fabric-gateway-preset.yaml`)로 게이트웨이 `POST /gw/**`만 연다.
> - 여권은 OpenShell provider에 넣는다. OpenClaw가 보는 건 자리표시자뿐이다.
> - 스킬(`skills/fabric-access`)과 도우미 스크립트로 OpenClaw가 사내 MCP 도구를 부른다.

검증한 버전은 NemoClaw v0.0.124, OpenShell 0.0.116, OpenClaw 2026.7.1, 모델은 Nemotron 3 Nano 30B(로컬 Ollama)다. direct 도구 공개는 `rebuild --tool-disclosure direct`로 확인했고, 온보딩 때 환경변수로 주는 방법은 NemoClaw 문서에 있는 방법이다.

## 순서

```bash
# 0) 데이터 노드와 게이트웨이는 먼저 띄워 둔다
./scripts/data-node-up.sh && ./scripts/agent-node-up.sh

# 1) NemoClaw 온보딩 (로컬 모델, direct 도구 공개)
export NEMOCLAW_GATEWAY_PORT=8990           # 8080이 비어 있으면 생략
NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1 \
NEMOCLAW_AGENT=openclaw NEMOCLAW_PROVIDER=custom \
NEMOCLAW_ENDPOINT_URL=http://localhost:8011/v1 NEMOCLAW_MODEL=nemotron-3-nano:30b \
NEMOCLAW_COMPATIBLE_AUTH_MODE=none NEMOCLAW_TOOL_DISCLOSURE=direct \
NEMOCLAW_SANDBOX_NAME=fabric-claw nemoclaw onboard --non-interactive

# 2) 게이트웨이 길만 연다
nemoclaw fabric-claw policy add --from-file agent-node/nemoclaw/fabric-gateway-preset.yaml --yes

# 3) 여권을 provider로 넣고 샌드박스에 붙인다
G=nemoclaw-$NEMOCLAW_GATEWAY_PORT
openshell provider profile import --gateway $G -f agent-node/openshell/fabric-gateway-profile.yaml
export FABRIC_CAPABILITY="$(fabric grant mcp://ledger-read --ttl 2h --json | jq -r .token)"
openshell provider create --gateway $G --name fabric --type agent-fabric-gateway --credential FABRIC_CAPABILITY
openshell sandbox provider attach --gateway $G fabric-claw fabric
openshell sandbox stop --gateway $G fabric-claw && openshell sandbox start --gateway $G fabric-claw

# 4) 스킬 설치 후 일 시키기
nemoclaw fabric-claw skill install skills/fabric-access
openshell sandbox exec --gateway $G --name fabric-claw -- \
  openclaw agent --session-id demo -m "fabric-access 스킬을 따라 최근 30일 위험 거래처를 점검하고 한도 축소를 준비만 해줘"
```

## 걸렸던 곳

| 증상 | 원인 | 해결 |
| --- | --- | --- |
| OpenClaw가 "도구가 없다"며 아무것도 안 함 | 기본값인 Tool Search 모드에서 작은 모델이 `exec`를 못 찾음 | `NEMOCLAW_TOOL_DISCLOSURE=direct` 또는 `nemoclaw <sb> rebuild --tool-disclosure direct` |
| rebuild가 `compatible-endpoint` 자격 증명 재사용 불가로 멈춤 | 인증 없는 로컬 엔드포인트 | rebuild 때 `COMPATIBLE_API_KEY`에 아무 값 |
| rebuild 뒤 여권이 사라짐 | rebuild가 직접 붙인 provider를 떼어 냄 | 3번의 attach를 다시 |
| 샌드박스 셸에는 여권이 있는데 OpenClaw에는 없음 | provider는 프로세스가 뜰 때 들어감 | `openshell sandbox stop` → `start` |
| 모델이 `FABRIC_CAPABILITY`를 가짜 값으로 덮어씀, curl 따옴표가 깨져 `policy_denied` | 작은 모델의 셸 인용 실수 | 스킬의 `fabric_mcp.py` 사용 |
| `policy add`가 "policy state is unavailable" | 기본 포트가 아닌 게이트웨이 | 모든 `nemoclaw` 명령에 `NEMOCLAW_GATEWAY_PORT` |
| Docker 연결 실패 | 기본이 아닌 Docker context | `DOCKER_CONTEXT=default` |
| 모델 검증 시간 초과 | 첫 로드가 느림 | 온보딩 전에 모델을 한 번 불러 둔다 |

## 확인한 것

샌드박스 안에서 직접 실행한 결과다.

| 확인 | 결과 |
| --- | --- |
| `echo $FABRIC_CAPABILITY` | `openshell:resolve:env:…` (자리표시자) |
| `ledger-read` 도구 목록·호출 | 200 |
| `ledger-admin` 호출 | 403 capability denied |
| `audit-drop.example.net` 업로드 | 차단 (curl 56) |
