#!/usr/bin/env bash
set -euo pipefail

if ! command -v wetware >/dev/null 2>&1; then
  echo "wetware binary not found on PATH" >&2
  exit 1
fi

if [ $# -lt 1 ]; then
  echo "Usage: $0 <transcript_or_summary_file> [duration_minutes] [depth_1_to_10]" >&2
  exit 1
fi

input="$1"
duration_minutes="${2:-25}"
depth="${3:-3}"

if [ ! -f "$input" ]; then
  echo "Input file not found: $input" >&2
  exit 1
fi

wetware auto-imprint "$input" --duration_minutes "$duration_minutes" --depth "$depth"
