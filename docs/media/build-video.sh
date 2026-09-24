#!/usr/bin/env bash
# 제출용 종합 영상: 실제 녹화본 사이에 짧은 한국어 자막 카드를 넣어 이어 붙인다.
# 녹화본은 손대지 않는다(배속·편집 없음). 카드만 새로 만든다.
set -euo pipefail
cd "$(dirname "$0")"
FONT=/System/Library/Fonts/AppleSDGothicNeo.ttc
W=1600; H=1000; T=$(mktemp -d)
card() { # card <out> <seconds> <title> <sub>
  uv run -q --with pillow python cards.py "$T/card.png" "$3" "$4"
  ffmpeg -y -v error -loop 1 -t "$2" -i "$T/card.png" -vf fps=30 -c:v libx264 -pix_fmt yuv420p "$1"
}
fit() { ffmpeg -y -v error -i "$1" -vf "scale=${W}:${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:color=0x0b1020,fps=30" -an -c:v libx264 -pix_fmt yuv420p "$2"; }
still() { ffmpeg -y -v error -loop 1 -t "$2" -i "$1" -vf "scale=${W}:${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:color=0x0b1020,fps=30" -c:v libx264 -pix_fmt yuv420p "$3"; }

card $T/00.mp4 4 "Secure Agent Passport" "모델이 속아도 사고가 나지 않는 핀테크 AI 에이전트"
card $T/01.mp4 5 "망분리가 풀려도 에이전트는 못 쓰고 있다" "무엇을 몇 분 동안 쓰게 할지 정할 수도, 무엇이 나갔는지 증명할 수도 없어서"
card $T/02.mp4 3 "구조" "기계 안은 OpenShell, 기계 사이는 Agent Fabric 게이트웨이"
fit architecture-tour.mp4 $T/03.mp4
card $T/04.mp4 3 "실제 실행 · 공격과 자동 정지" "심어 둔 메모가 유출을 시킨다. 녹화 그대로, 편집 없음"
fit watch-demo.mp4 $T/05.mp4
card $T/06.mp4 3 "에이전트가 스스로 판단" "위험 거래처 전부 점검 → 심각한 두 곳만 한도 조정 준비"
still ../screenshots/13-portfolio-run.png 7 $T/07.mp4
card $T/08.mp4 3 "서비스 흐름" "토큰은 에이전트를 거치지 않는다"
fit service-flow-tour.mp4 $T/09.mp4
card $T/10.mp4 5 "github.com/falcons-eyes/agent-fabric-openshell-recipe" "팔콘아이즈 · 모든 화면은 실제 실행 결과"
ls $T/*.mp4 | sed "s|^|file '|; s|$|'|" > $T/list.txt
ffmpeg -y -v error -f concat -safe 0 -i $T/list.txt -c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart secure-agent-passport-demo.mp4
rm -rf $T
echo "wrote secure-agent-passport-demo.mp4"
