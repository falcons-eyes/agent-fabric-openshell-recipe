# 시연

**전부 실제 실행 화면이다.** 명령을 터미널에서 실제로 돌리고, 나온 출력을 그대로 이미지로 옮겼다. 옆에 있는 `.txt`가 그 원본 출력이다. 환경은 Mac 한 대(두 노드 겸용), OpenShell 0.0.116, Nemotron 3 Nano 30B, Agent Fabric staging이다.

## 한눈에

![계획 이탈 시 자동 정지](media/watch-demo.gif)

공격 → 게이트웨이 거부 → 계획 감시기가 이탈을 잡고 freeze → 다음 호출 403. [MP4](media/watch-demo.mp4)

## 장면별

| # | 장면 | 한 줄 |
| --- | --- | --- |
| 1 | ![](screenshots/01-services.png) | 데이터 노드의 두 서비스는 사설망 안에만 있다. 공개 포트는 없다. |
| 2 | ![](screenshots/02-grant.png) | 여권: `ledger-read` 하나, MCP 메서드 4개, 30분. |
| 3 | ![](screenshots/03-provider.png) | 여권은 OpenShell provider에 들어간다. 게이트웨이로 가는 요청에만 붙는다. |
| 4 | ![](screenshots/04-placeholder.png) | 샌드박스 안에서 보이는 건 자리표시자뿐. 새어 나갈 진짜 값이 없다. |
| 5 | ![](screenshots/05-agent-run.png) | 에이전트가 찾고, 요약하고, 한도 변경은 준비만 한다. 가드레일이 메모를 걸렀고, 경고는 코드가 붙였다. |
| 6 | ![](screenshots/06-attacks.png) | 메모가 시키는 공격을 모델 없이 그대로 실행해도 둘 다 403. |
| 7 | ![](screenshots/07-ledger.png) | 원장: 맨 윗줄이 공격 시도. `ledger-admin`, 403, 반출 0바이트. |
| 8 | ![](screenshots/08-freeze.png) | 긴급 정지: 200 → 403 → 200. |
| 9 | ![](screenshots/09-datanode-log.png) | 데이터 노드 기록에 `export_transactions`가 아예 없다. |
| 10 | ![](screenshots/10-approval.png) | 사람이 승인하고, 승인자 이름이 남는다. |
| 11 | ![](screenshots/11-guardrail-policy.png) | 가드레일 정책은 NVIDIA 스킬로 만들고 스키마 검증을 통과했다. |
| 12 | ![](screenshots/12-plan-watch.png) | 계획에 없는 호출이 나오자마자 게이트웨이가 스스로 멈춘다. |

## 참고할 점

- 5번의 가드레일 모델은 대체 모델(`nemotron-3-nano:30b`)이다. 정식 모델은 build.nvidia.com의 `nemotron-3.5-content-safety`다.
- 4번의 `sleep 2`는 OpenShell 0.0.116에서 바로 끝나는 명령이 준비 단계에서 오류로 처리돼서 넣었다.
- 긴 출력은 이미지로 옮길 때만 110자에서 줄을 바꿨다. 원본 `.txt`는 그대로다.
- 장면마다 따로 실행해서 승인 번호가 서로 다를 수 있다.
