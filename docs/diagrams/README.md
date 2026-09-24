# 다이어그램

[archify](https://github.com/tt-a1i/archify)로 만든 대화형 다이어그램이다. 원본은 JSON 명세이고, 산출물은 외부 의존이 없는 단일 HTML이다. 브라우저로 열면 확대·검색·경로 추적·챕터 재생이 된다.

| 다이어그램 | 원본 명세 | 대화형 HTML | 움직이는 이미지 |
| --- | --- | --- | --- |
| 시스템 아키텍처 | [system.architecture.json](system.architecture.json) | [열기](https://falcons-eyes.github.io/agent-fabric-openshell-recipe/docs/diagrams/system-architecture.html) | [GIF](system-architecture.gif) · [WebM](system-architecture.webm) |
| 서비스 흐름 | [service-flow.sequence.json](service-flow.sequence.json) | [열기](https://falcons-eyes.github.io/agent-fabric-openshell-recipe/docs/diagrams/service-flow.html) | [GIF](service-flow.gif) · [WebM](service-flow.webm) |

**만든 방법과 검증 결과**

- 두 명세 모두 `archify validate --quality showcase`를 통과했다. 9개 산출물 검사를 모두 통과했고, 구성 오류와 경고는 0이다.
- HTML은 `archify deliver`로 만들었다. 명세와 산출물의 SHA-256은 전달 영수증에 기록된다.
- `archify visual-check`로 실제 브라우저에서 1440×900, 1600×1000, 1920×1080, 2048×1320의 라이트·다크 테마를 확인했다. 넘침 없음, 가독성 통과. 결과는 `*.visual-check.json`과 스크린샷에 있다.
- WebM은 HTML 뷰어의 **Export → WebM**(archify 내장 기능)으로 받았다. GIF는 그 WebM을 ffmpeg로 변환한 것이다.

**그림에 담은 것과 담지 않은 것**

- 노드와 연결은 이 레포의 코드와 실제 실행에서 확인한 것만 그렸다.
- 계획용 모델과 가드레일은 같은 로컬 모델 서버를 쓰므로 한 노드로 그렸다.
- 서비스 흐름에서는 모델의 계획 단계와 한도 변경 준비 호출을 생략했다. 두 호출도 같은 프록시·게이트웨이 검사를 거친다.
- "에이전트 노드 · DGX Spark"는 목표 배치다. 현재 기록된 실행은 Mac 한 대가 두 노드를 겸했다. 자세한 내용은 [VERIFICATION.md](../VERIFICATION.md)에 있다.
