#!/usr/bin/env bash
# One-time fix for IndoDesk User daemon install (app name contains a space).
set -euo pipefail

APP_NAME="IndoDesk User"
BUNDLE_ID="com.carriez.rustdesk"
PREFS_ID="com.carriez.IndoDesk"
USER_NAME="$(whoami)"

DAEMON_LEGACY="/Library/LaunchDaemons/com.indoteknisi.indodesk.user.IndoDesk User_service.plist"
AGENT_LEGACY="/Library/LaunchAgents/com.indoteknisi.indodesk.user.IndoDesk User_server.plist"
PREFS_SRC="/Users/${USER_NAME}/Library/Preferences/${PREFS_ID}"
PREFS_DST="/var/root/Library/Preferences/${PREFS_ID}"

read -r -d '' DAEMON_XML <<EOF || true
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${BUNDLE_ID}_service</string>
  <key>AssociatedBundleIdentifiers</key><string>${BUNDLE_ID}</string>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>1</integer>
  <key>ProgramArguments</key>
  <array>
    <string>/Applications/${APP_NAME}.app/Contents/MacOS/service</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>WorkingDirectory</key><string>/Applications/${APP_NAME}.app/Contents/MacOS/</string>
  <key>StandardErrorPath</key><string>/tmp/indodesk_user_service.err</string>
  <key>StandardOutPath</key><string>/tmp/indodesk_user_service.out</string>
</dict>
</plist>
EOF

read -r -d '' AGENT_XML <<EOF || true
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${BUNDLE_ID}_server</string>
  <key>AssociatedBundleIdentifiers</key><string>${BUNDLE_ID}</string>
  <key>LimitLoadToSessionType</key>
  <array><string>LoginWindow</string><string>Aqua</string></array>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key><false/>
    <key>AfterInitialDemand</key><false/>
  </dict>
  <key>ThrottleInterval</key><integer>1</integer>
  <key>RunAtLoad</key><true/>
  <key>ProgramArguments</key>
  <array>
    <string>/Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME}</string>
    <string>--server</string>
  </array>
  <key>WorkingDirectory</key><string>/Applications/${APP_NAME}.app/Contents/MacOS/</string>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF

TMPD="$(mktemp -d)"
echo "$DAEMON_XML" > "${TMPD}/daemon.plist"
echo "$AGENT_XML" > "${TMPD}/agent.plist"

osascript <<APPLESCRIPT
set daemonFile to POSIX file "${TMPD}/daemon.plist"
set agentFile to POSIX file "${TMPD}/agent.plist"
set daemonPlist to "${DAEMON_LEGACY}"
set agentPlist to "${AGENT_LEGACY}"
set daemonCanonical to "/Library/LaunchDaemons/${BUNDLE_ID}_service.plist"
set agentCanonical to "/Library/LaunchAgents/${BUNDLE_ID}_server.plist"
set prefsSrc to "${PREFS_SRC}"
set prefsDst to "${PREFS_DST}"

set sh to "rm -f /Library/LaunchDaemons/com.carriez.IndoDesk /Library/LaunchAgents/com.carriez.IndoDesk; " ¬
  & "cp " & quoted form of POSIX path of daemonFile & " " & quoted form of daemonCanonical & " && chown root:wheel " & quoted form of daemonCanonical & "; " ¬
  & "cp " & quoted form of POSIX path of agentFile & " " & quoted form of agentCanonical & " && chown root:wheel " & quoted form of agentCanonical & "; " ¬
  & "cp " & quoted form of POSIX path of daemonFile & " " & quoted form of daemonPlist & " && chown root:wheel " & quoted form of daemonPlist & "; " ¬
  & "cp " & quoted form of POSIX path of agentFile & " " & quoted form of agentPlist & " && chown root:wheel " & quoted form of agentPlist & "; " ¬
  & "mkdir -p " & quoted form of prefsDst & "; " ¬
  & "cp -f " & quoted form of (prefsSrc & "/IndoDesk.toml") & " " & quoted form of (prefsDst & "/") & " 2>/dev/null || true; " ¬
  & "cp -f " & quoted form of (prefsSrc & "/IndoDesk2.toml") & " " & quoted form of (prefsDst & "/") & " 2>/dev/null || true; " ¬
  & "launchctl bootout system " & quoted form of daemonCanonical & " 2>/dev/null || true; " ¬
  & "launchctl bootstrap system " & quoted form of daemonCanonical & " 2>/dev/null || launchctl load -w " & quoted form of daemonCanonical & "; " ¬
  & "launchctl bootout gui/$(id -u) " & quoted form of agentCanonical & " 2>/dev/null || true; " ¬
  & "launchctl bootstrap gui/$(id -u) " & quoted form of agentCanonical & " 2>/dev/null || launchctl load -w " & quoted form of agentCanonical

do shell script sh with prompt "IndoDesk User ingin memasang layanan sistem (daemon)" with administrator privileges
APPLESCRIPT

rm -rf "${TMPD}"
echo "Daemon terpasang:"
echo "  - ${DAEMON_LEGACY}"
echo "  - /Library/LaunchDaemons/${BUNDLE_ID}_service.plist"
echo "Agent terpasang:"
echo "  - ${AGENT_LEGACY}"
echo "  - /Library/LaunchAgents/${BUNDLE_ID}_server.plist"
echo "Quit IndoDesk User (Cmd+Q) lalu buka lagi."
