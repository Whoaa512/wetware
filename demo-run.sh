#!/bin/bash
# Demo script for wetware — the resonance loop
export WETWARE_DATA_DIR=/tmp/wetware-demo
rm -rf "$WETWARE_DATA_DIR"
mkdir -p "$WETWARE_DATA_DIR"
cp example/concepts.json "$WETWARE_DATA_DIR/"

# Scene 1: Fresh substrate
printf '\033[36m# fresh substrate — 15 concepts, all dormant\033[0m\n\n'
wetware briefing
sleep 3

clear

# Scene 2: Imprint + see what lit up
printf '\033[36m# imprint what came up in a conversation\033[0m\n'
printf '$ wetware imprint "coding, creativity, music"\n\n'
wetware imprint "coding, creativity, music" --steps 5 >/dev/null

printf '\033[36m# charge propagated through the substrate\033[0m\n\n'
wetware briefing
sleep 3

clear

# Scene 3: Dream + see what emerged
printf '\033[36m# dream: random stimulation finds connections\033[0m\n'
printf '$ wetware dream --steps 20\n\n'
wetware dream --steps 20 >/dev/null

printf '\033[36m# new concepts warmed up through resonance\033[0m\n\n'
wetware briefing
sleep 4
