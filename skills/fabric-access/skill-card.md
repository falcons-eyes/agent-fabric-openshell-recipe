# 스킬 카드: fabric-access

| 항목 | 값 |
| --- | --- |
| 이름 | fabric-access |
| 버전 | 0.1.0 |
| 소유 | 팔콘아이즈 (Falcon Eyes Inc., Agent Fabric 팀) |
| 라이선스 | Apache-2.0 |
| 형식 | Agent Skills 규격 (`SKILL.md`) |
| 대상 | NVIDIA OpenShell 안에서 도는 에이전트 (NemoClaw의 OpenClaw, 또는 HTTP 호출이 되는 에이전트) |

## 하는 일

에이전트가 Agent Fabric 게이트웨이를 거쳐 다른 서버의 MCP·A2A·LLM 서비스를 부르는 법, 게이트웨이 거부 응답을 읽는 법, 승인이 필요한 조치를 다루는 법을 알려 준다.

## 필요한 것

- 샌드박스에서 닿는 Agent Fabric 게이트웨이 (`fabric gateway proxy`)
- 게이트웨이 주소에 `FABRIC_CAPABILITY`를 주입하는 OpenShell provider
- 환경 변수 `FABRIC_GATEWAY_URL`, `FABRIC_NETWORK`

## 한계

- 안내일 뿐 강제하지 않는다. 강제는 OpenShell 프록시와 게이트웨이가 하고, 모델이 이 스킬을 무시해도 그대로 유지된다.
- 스크립트가 없고, 아무것도 실행하거나 읽지 않는다.
- NVIDIA 검증 스킬 절차(스캔·서명)는 아직 거치지 않았다.
