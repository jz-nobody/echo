#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/AgentIsland"
DIST_DIR="$ROOT_DIR/build"
APP_BUNDLE="$DIST_DIR/Echo.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
PROCESS_NAME="AgentIsland"
BUNDLE_ID="com.agentisland.app"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true

swift build --package-path "$PACKAGE_DIR"
BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES/Sounds"
cp "$PACKAGE_DIR/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$BIN_DIR/AgentIsland" "$APP_MACOS/AgentIsland"
cp "$BIN_DIR/agent-island-bridge" "$APP_MACOS/agent-island-bridge"
cp "$PACKAGE_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp "$PACKAGE_DIR/Resources/Sounds/"*.wav "$APP_RESOURCES/Sounds/"
chmod +x "$APP_MACOS/AgentIsland" "$APP_MACOS/agent-island-bridge"
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_runtime() {
  swift test --package-path "$PACKAGE_DIR"
  open_app

  local attempt
  for attempt in $(seq 1 20); do
    if pgrep -x "$PROCESS_NAME" >/dev/null && [ -S /tmp/agent-island-codex.sock ]; then
      break
    fi
    /bin/sleep 1
  done

  pgrep -x "$PROCESS_NAME" >/dev/null
  [ -S /tmp/agent-island-codex.sock ]
  [ -x "$HOME/.agent-island/bin/agent-island-bridge" ]

  local hooks_ready=0
  for attempt in $(seq 1 20); do
    if verify_codex_hooks 2>/dev/null; then
      hooks_ready=1
      break
    fi
    /bin/sleep 1
  done
  if [ "$hooks_ready" -ne 1 ]; then
    verify_codex_hooks
  fi

  echo "Echo verified: tests passed, app running, Codex socket ready, hooks installed."
}

verify_codex_hooks() {
  python3 - "$HOME/.codex/hooks.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    hooks = json.load(handle).get("hooks", {})

for event in ("PermissionRequest", "PreToolUse"):
    entries = hooks.get(event, [])
    installed = [
        hook
        for entry in entries
        for hook in entry.get("hooks", [])
        if "agent-island-bridge --source codex" in hook.get("command", "")
    ]
    if not installed:
        raise SystemExit(f"missing Echo Codex hook: {event}")
    if installed[0].get("timeout") != 86400:
        raise SystemExit(f"unexpected Echo Codex hook timeout for {event}: {installed[0].get('timeout')}")
PY
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_MACOS/AgentIsland"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\" OR process == \"$PROCESS_NAME\""
    ;;
  --verify|verify)
    verify_runtime
    ;;
esac
