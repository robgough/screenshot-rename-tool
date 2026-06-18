#!/bin/zsh
# Stop and remove the launchd LaunchAgent (does not delete the binary or any renamed files).
LABEL="net.robgough.screenshot-renamer"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "Unloaded and removed $LABEL"
