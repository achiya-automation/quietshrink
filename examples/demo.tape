# vhs tape — generates a demo GIF for quietshrink
# Run from project root: vhs examples/demo.tape
# Requires: /tmp/recording.mov (sample screen recording)

Output examples/demo.gif

Set FontSize 14
Set Width 1100
Set Height 480
Set Theme "Catppuccin Mocha"
Set Padding 20
Set TypingSpeed 30ms
Set Shell "bash"

Type "cd /tmp" Enter
Sleep 200ms
Type "ls -lh recording.mov" Enter
Sleep 1500ms

Type "/Users/am/quietshrink/bin/quietshrink recording.mov" Enter
Sleep 6s

Type "ls -lh recording*.mov" Enter
Sleep 3s
