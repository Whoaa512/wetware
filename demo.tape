# Wetware Demo — Real production system after 12K+ steps
# Shows: status → briefing → introspect

Output demo.gif

Require wetware

Set Shell "zsh"
Set FontSize 15
Set Width 1000
Set Height 700
Set Padding 20
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set TypingSpeed 35ms
Set PlaybackSpeed 2

# Scene 1: Status overview
Sleep 1s
Type "wetware status"
Enter
Sleep 8s

# Scene 2: Imprint some concepts
Type "wetware imprint 'curiosity, emergence, play'"
Enter
Sleep 8s

# Scene 3: Check what resonates
Type "wetware briefing"
Enter
Sleep 10s

# Scene 4: Deep introspection
Type "wetware introspect --top 5"
Enter
Sleep 12s

# Final pause
Sleep 3s
