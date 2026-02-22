# Wetware Quick Start Demo
# Shows: init → add concepts → imprint → briefing → dream → briefing
# Run: cd ~/code/wetware && vhs demo-quickstart.tape
# Renders the "getting started from scratch" experience

Output demo-quickstart.gif

Require wetware

Set Shell "zsh"
Set FontSize 15
Set FontFamily "Menlo"
Set Width 1000
Set Height 550
Set TypingSpeed 35ms
Set Theme "Catppuccin Mocha"
Set Padding 16
Set WindowBar Colorful
Set BorderRadius 8

# Pre-setup: clean temp dir with example concepts
Hide
Type@0 "rm -rf /tmp/wetware-demo && mkdir -p /tmp/wetware-demo"
Enter
Sleep 500ms
Type@0 "cp /Users/cjw/code/wetware/example/concepts.json /tmp/wetware-demo/"
Enter
Sleep 500ms
Type@0 "export WETWARE_DATA_DIR=/tmp/wetware-demo"
Enter
Sleep 500ms
Type@0 "clear"
Enter
Sleep 500ms
Show

# Step 1: Set the data dir
Type "export WETWARE_DATA_DIR=/tmp/wetware-demo"
Enter
Sleep 800ms

# Step 2: Empty gel — nothing resonating
Type "wetware briefing"
Enter
Sleep 3s

# Step 3: Imprint from a task
Type "wetware imprint 'coding, creativity, music' --steps 5"
Enter
Sleep 3s

# Step 4: See what lit up
Type "wetware briefing"
Enter
Sleep 4s

# Step 5: Dream — random stimulation
Type "wetware dream --steps 10"
Enter
Sleep 2.5s

# Step 6: What emerged?
Type "wetware briefing"
Enter
Sleep 5s

Sleep 3s
