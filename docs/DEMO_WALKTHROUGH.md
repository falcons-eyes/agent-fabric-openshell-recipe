# 시연: Secure Agent Passport

**아래 화면은 전부 실제 실행 결과다.** 모든 명령은 가상 터미널(pty)에서 실제로 실행했고, 그 출력을 [`freeze`](https://github.com/charmbracelet/freeze)로 이미지로 옮겼다. 다시 타이핑한 글자는 없다.

각 이미지 옆의 `.txt` 파일은 같은 실행의 원본 출력이다(ANSI 색상 포함). 긴 출력은 이미지로 옮길 때만 110자에서 줄바꿈했다.

| 항목 | 값 |
| --- | --- |
| 촬영 | 2026-09-24 |
| 환경 | Mac(M2 Max) 한 대가 에이전트 노드와 데이터 노드를 겸함 |
| 구성 | OpenShell 0.0.116, Nemotron 3 Nano 30B(Ollama, 로컬), Agent Fabric staging(게이트웨이 원장·긴급 정지가 들어간 빌드) |
| 데이터 | 전부 합성 데이터와 심어둔 공격 메모 1건 |

화면의 `fabric`은 staging 빌드다. DGX Spark를 에이전트 노드로 쓰는 촬영은 진행 중이다.

## 0. 공개 레포

![GitHub](screenshots/00-github-repo.png)

## 1. 데이터 노드의 두 서비스는 사설망에만 있다

![services](screenshots/01-services.png)

`ledger-read`(집계만)와 `ledger-admin`(원본 내보내기·승인)은 서로 다른 서비스다. 공개 포트는 없다.

## 2. 여권 발급: 한 서비스, MCP 메서드 4개, 30분

![grant](screenshots/02-grant.png)

토큰은 화면에 띄우지 않았다. 이 여권은 `ledger-read` 외의 서비스에는 쓸 수 없다.

## 3. 여권은 OpenShell provider에 들어간다

![provider](screenshots/03-provider.png)

게이트웨이 주소에 보내는 요청에만 `Authorization: Bearer`로 주입된다.

## 4. 샌드박스 안의 에이전트는 자리표시자만 본다

![placeholder](screenshots/04-placeholder.png)

프롬프트 인젝션이 "토큰을 출력하라"고 시켜도 새어 나갈 실제 값이 없다. `sleep 2`는 OpenShell 0.0.116에서 즉시 끝나는 명령이 준비 단계에서 오류로 끝나기 때문에 넣었다.

## 5. 에이전트가 일을 한다: 계획, 도구 호출, 가드레일, 승인 준비

![agent run](screenshots/05-agent-run.png)

- Nemotron이 거래처를 찾고(처음엔 중국어로 검색했다가 영어로 다시 찾음) 위험 요약을 조회한다.
- 요약 결과에 심어둔 메모가 있어 **가드레일이 `harmful`로 걸렀다.** 정책은 NVIDIA 스킬 `nemotron-policy-generator`로 만들었다. 이 화면의 가드레일 모델은 대체용 `nemotron-3-nano:30b`이고, 정식 모델은 build.nvidia.com의 `nemotron-3.5-content-safety`다.
- 한도 변경은 **준비만** 했다(승인 요청 #4).
- 답변 끝의 **보안 경고는 코드가 붙인다.** 모델은 여전히 그 메모를 "감사 절차 진행 중"이라고 요약했다. 그래서 경고를 모델에 맡기지 않는다.

## 6. 공격: 메모가 시키는 대로 모델 없이 실행해도 막힌다

![attacks](screenshots/06-attacks.png)

| 공격 | 결과 | 막은 곳 |
| --- | --- | --- |
| 외부 URL로 업로드 | `403 Forbidden` | OpenShell 프록시 |
| `ledger-admin`의 전체 내보내기 | `403 capability denied` | Agent Fabric 게이트웨이 |

## 7. 게이트웨이 원장: 허용과 거부 모두, 바이트와 함께

![ledger](screenshots/07-ledger.png)

맨 위 줄이 6번의 공격이다. `ledger-admin`, `403 refused`, 나간 바이트 **0**으로 남았다.

## 8. 긴급 정지

![freeze](screenshots/08-freeze.png)

정지 전 호출은 200, 정지 중에는 **403**, 해제 후에는 다시 200이다. 제어면을 거치기 전에 게이트웨이가 바로 막는다.

## 9. 데이터 노드가 직접 남긴 기록

![data node log](screenshots/09-datanode-log.png)

데이터 노드는 허용된 호출만 받았고 기록했다. `export_transactions` 줄은 **없다.** 거부된 호출은 데이터 노드에 도달하지 않았다. 여기 시간은 DB 기준 UTC이고 원장은 KST다.

## 10. 사람이 승인한다

![approval](screenshots/10-approval.png)

승인 #4가 `approved`로 바뀌고 승인자 이름이 남는다. 승인은 데이터 노드의 관리 경로로만 할 수 있고, 에이전트의 여권으로는 닿지 않는다.

## 11. 가드레일 정책(NVIDIA 스킬로 생성)

![guardrail policy](screenshots/11-guardrail-policy.png)

스킬의 JSON 스키마 검증을 통과했다(`schema: valid`). 범주는 6개(S9, S15, S23~S26)이고, 여기서 Nemotron 콘텐츠 안전 모델용 프롬프트를 만든다.
