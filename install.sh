#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${WETWARE_INSTALL_DIR:-$HOME/.local/bin}"

echo "🧬 Installing Wetware..."

# --- Check / install Elixir ---
if ! command -v elixir &>/dev/null; then
  echo ""
  echo "Elixir not found. Wetware needs Erlang/OTP 26+ and Elixir 1.16+."
  echo ""

  if command -v asdf &>/dev/null; then
    echo "Installing via asdf..."
    asdf plugin add erlang 2>/dev/null || true
    asdf plugin add elixir 2>/dev/null || true
    asdf install erlang latest
    asdf install elixir latest
    asdf global erlang latest
    asdf global elixir latest
  elif command -v brew &>/dev/null; then
    echo "Installing via Homebrew..."
    brew install erlang elixir
  else
    echo "Please install Elixir first: https://elixir-lang.org/install.html"
    exit 1
  fi
fi

# --- Verify versions ---
elixir_version=$(elixir --version | grep "Elixir" | awk '{print $2}')
echo "Using Elixir $elixir_version"

# --- Build ---
echo "Building escript..."
mix local.hex --force --if-missing
mix local.rebar --force --if-missing
mix deps.get
mix escript.build

# --- Install ---
mkdir -p "$INSTALL_DIR"
cp wetware "$INSTALL_DIR/wetware"
chmod +x "$INSTALL_DIR/wetware"

# --- Init ---
if [ ! -f "${WETWARE_DATA_DIR:-$HOME/.config/wetware}/concepts.json" ]; then
  echo "Initializing config..."
  "$INSTALL_DIR/wetware" init
fi

echo ""
echo "✅ Wetware installed to $INSTALL_DIR/wetware"

# Check PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo ""
  echo "⚠️  $INSTALL_DIR is not in your PATH. Add it:"
  echo "   export PATH=\"$INSTALL_DIR:\$PATH\""
fi

echo ""
echo "Get started:"
echo "  wetware imprint \"curiosity, coding\" --steps 10"
echo "  wetware briefing"
echo "  wetware dream --steps 20"
