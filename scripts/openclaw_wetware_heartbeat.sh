#!/usr/bin/env bash
set -euo pipefail

if ! command -v wetware >/dev/null 2>&1; then
  echo "wetware binary not found on PATH" >&2
  exit 1
fi

if ! command -v openclaw >/dev/null 2>&1; then
  echo "openclaw CLI not found on PATH" >&2
  exit 1
fi

briefing="$(wetware briefing 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-600)"
timestamp="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

openclaw system event \
  --mode next-heartbeat \
  --text "Wetware heartbeat ${timestamp}: ${briefing}"
