#!/bin/bash
# Build the bridge and run it in the background as a macOS LaunchAgent.
# It starts at login and is restarted whenever it exits (e.g. after being logged out).
#
#   ./install-launchd.sh            install (or reinstall after pulling changes)
#   ./install-launchd.sh uninstall  stop and remove the agent
#
# Environment variables (remembered on reinstall):
#   WHATSAPP_BRIDGE_PORT  REST API port, default 8080. Use a different port per clone
#                         when running one bridge per WhatsApp number.
#   WHATSAPP_NOTIFY_URL   e.g. https://ntfy.sh/<your-topic>, to also get
#                         re-authentication alerts on your phone.
set -euo pipefail

cd "$(dirname "$0")"
DIR="$(pwd)"
# One agent per clone, named after the clone's directory
CLONE="$(basename "$(dirname "$DIR")" | tr -c 'A-Za-z0-9.\n-' '-')"
LABEL="com.whatsapp-mcp.bridge.$CLONE"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

# Reuse settings from a previous install unless overridden
previous() {
  [ -f "$PLIST" ] && /usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:$1" "$PLIST" 2>/dev/null || true
}
PORT="${WHATSAPP_BRIDGE_PORT:-$(previous WHATSAPP_BRIDGE_PORT)}"
PORT="${PORT:-8080}"
NOTIFY_URL="${WHATSAPP_NOTIFY_URL:-$(previous WHATSAPP_NOTIFY_URL)}"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

if [ "${1:-}" = "uninstall" ]; then
  rm -f "$PLIST"
  echo "Removed $LABEL"
  exit 0
fi

# Give the old instance a moment to release the port, then make sure nothing else holds it
sleep 1
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is already in use (another bridge?). Set WHATSAPP_BRIDGE_PORT to a free port." >&2
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2
  exit 1
fi

go build -o whatsapp-bridge .

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$DIR/whatsapp-bridge</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$DIR</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>WHATSAPP_BRIDGE_PORT</key>
    <string>$PORT</string>
    <key>WHATSAPP_NOTIFY_URL</key>
    <string>$NOTIFY_URL</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>30</integer>
  <key>StandardOutPath</key>
  <string>$DIR/whatsapp.log</string>
  <key>StandardErrorPath</key>
  <string>$DIR/whatsapp.log</string>
</dict>
</plist>
EOF

launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Installed $LABEL on port $PORT. Logs: $DIR/whatsapp.log"
echo "If it needs to be linked, open http://localhost:$PORT/qr"
