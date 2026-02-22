# Wetware Demo — Real production system after 12K+ steps
# Shows: status → imprint → briefing → introspect

Output demo.gif

Require wetware

Set Shell "zsh"
Set FontSize 16
Set Width 1000
Set Height 650
Set Padding 20
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set TypingSpeed 40ms
Set PlaybackSpeed 1.5

# Scene 1: Status overview
Sleep 500ms
Type "wetware status"
Enter
Sleep 4s

# Scene 2: Imprint some concepts
Type "wetware imprint 'curiosity, emergence, play'"
Enter
Sleep 4s

# Scene 3: Quick dream cycle
Type "wetware dream --steps 5"
Enter
Sleep 5s

# Scene 4: Check what resonates
Type "wetware briefing"
Enter
Sleep 6s

# Scene 5: Deep introspection
Type "wetware introspect --top 5"
Enter
Sleep 8s

# Pause at end
Sleep 2s
