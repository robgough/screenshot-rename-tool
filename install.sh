#!/bin/zsh
# Build the binary and load the background watcher as a launchd LaunchAgent.
#
# Usage: ./install.sh [screenshot-folder]
#   With no argument it prompts (defaulting to the current macOS screenshot location,
#   or the folder a previous install was already watching).
set -e
ARG="$1"                       # optional screenshot dir, captured before cd
cd "$(dirname "$0")"
ROOT="$PWD"
BIN="$ROOT/screenshot-renamer"
LABEL="net.robgough.screenshot-renamer"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# 1. Build if needed.
[ -x "$BIN" ] || ./build.sh

# 2. Decide which folder to watch.
#    Default priority: folder a previous install watched -> macOS screenshot location -> ~/Desktop.
DEFAULT_DIR=""
if [ -f "$PLIST" ]; then
    DEFAULT_DIR=$(defaults read "$PLIST" ProgramArguments 2>/dev/null | grep '"' | tail -1 | sed 's/.*"\(.*\)".*/\1/')
    case "$DEFAULT_DIR" in /*|"~"*) ;; *) DEFAULT_DIR="" ;; esac   # ignore if it isn't a path
fi
[ -z "$DEFAULT_DIR" ] && DEFAULT_DIR=$(defaults read com.apple.screencapture location 2>/dev/null || true)
[ -z "$DEFAULT_DIR" ] && DEFAULT_DIR="$HOME/Desktop"
DEFAULT_DIR="${DEFAULT_DIR/#\~/$HOME}"

if [ -n "$ARG" ]; then
    WATCHDIR="$ARG"
else
    printf "Screenshot folder to watch [%s]: " "$DEFAULT_DIR"
    read -r WATCHDIR || true
    [ -z "$WATCHDIR" ] && WATCHDIR="$DEFAULT_DIR"
fi
WATCHDIR="${WATCHDIR/#\~/$HOME}"
[ -d "$WATCHDIR" ] || echo "note: '$WATCHDIR' doesn't exist yet — the watcher will pick it up once it does."

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

# 3. Write the agent plist with this machine's real paths.
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
        <string>$WATCHDIR</string>
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

# 4. (Re)load it.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Loaded $LABEL"
echo "Watching: $WATCHDIR"
echo "Logs:     $HOME/Library/Logs/screenshot-renamer.log"
echo
echo "IMPORTANT: grant the binary Full Disk Access, or renames in protected folders"
echo "(Desktop/Documents) fail silently:"
echo "  System Settings > Privacy & Security > Full Disk Access > +  ->  $BIN"
echo "Then: ./install.sh again (or 'launchctl kickstart -k gui/$(id -u)/$LABEL')."
