# 계획 대비 자동 정지 시연 녹화 (VHS). 실제 실행을 그대로 녹화한다.
Output docs/media/watch-demo.mp4
Set Shell "bash"
Set FontFamily "Menlo"
Set FontSize 17
Set Width 1500
Set Height 860
Set Padding 24
Set Theme "Dracula"
Set TypingSpeed 45ms
Env FABRIC "/private/tmp/claude-501/-Users-jamesjoo-work-agent-fabric/bbdecdc2-04fe-4932-859b-4b694e418e83/scratchpad/bin/fabric-staging"
Hide
Type "export PS1='$ ' && clear" Enter
Show
Type "cat agent-node/watch/plan.json" Enter
Sleep 3s
Type "./scripts/watch-demo.sh" Enter
Wait+Screen@300s /frozen by operator/
Sleep 4s
