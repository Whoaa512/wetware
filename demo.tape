# Wetware Demo — the resonance loop
# Run: cd ~/code/wetware && vhs demo.tape

Output demo.gif

Require wetware

Set Shell "zsh"
Set FontSize 16
Set FontFamily "Menlo"
Set Width 900
Set Height 580
Set Padding 20
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set BorderRadius 8
Set TypingSpeed 30ms

# Run the demo script — handles setup, pauses, and screen clears
Type "bash demo-run.sh"
Enter
Sleep 20s
