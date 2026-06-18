#!/bin/zsh
# Build the binary and load the background watcher as a launchd LaunchAgent.
set -e
cd "$(dirname "$0")"
ROOT="$PWD"
BIN="$ROOT/screenshot-renamer"
LABEL="net.robgough.screenshot-renamer"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# 1. Build if needed.
[ -x "$BIN" ] || ./build.sh

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

# 2. Write the agent plist with this machine's real paths.
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
        <string>--watch</string>
        <string>--interval</string><string>4</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>ProcessType</key><string>Background</string>
    <key>StandardOutPath</key><string>$HOME/Library/Logs/screenshot-renamer.log</string>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/screenshot-renamer.log</string>
</dict>
</plist>
EOF

# 3. (Re)load it.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Loaded $LABEL"
echo "Logs: $HOME/Library/Logs/screenshot-renamer.log"
echo
echo "IMPORTANT: grant the binary access to your Documents folder, or renames will fail silently:"
echo "  System Settings > Privacy & Security > Full Disk Access > +  ->  $BIN"
echo "Then: ./install.sh again (or 'launchctl kickstart -k gui/$(id -u)/$LABEL')."
