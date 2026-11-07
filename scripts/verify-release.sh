#!/bin/sh
# Offline bundle checks: no HID access, no launchctl/SMAppService mutation.
set -eu
APP_PATH=${1:-Nibble.app}
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" = com.xppxpp.nibblecn
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleDisplayName' "$APP_PATH/Contents/Info.plist")" = 'Nibble 中文版'
ARCHS=$(lipo -archs "$APP_PATH/Contents/MacOS/nibble")
echo "$ARCHS" | /usr/bin/grep -q arm64
echo "$ARCHS" | /usr/bin/grep -q x86_64
codesign --verify --deep --strict "$APP_PATH"
"$APP_PATH/Contents/MacOS/nibble" distribution --json | python3 -c '
import json, sys
v = json.load(sys.stdin)
assert v["bundleID"] == "com.xppxpp.nibblecn", v
assert v["replayLabel"] == "com.xppxpp.nibblecn.replay", v
assert v["bundled"] is True, v
'
./nibble distribution --json | python3 -c '
import json, sys
v = json.load(sys.stdin)
assert v["replayLabel"] == "com.xppxpp.nibblecn.replay", v
assert v["bundled"] is False, v
'
"$APP_PATH/Contents/MacOS/nibble" version --json | python3 -c '
import json, plistlib, sys
with open(sys.argv[1], "rb") as f: info = plistlib.load(f)
assert json.load(sys.stdin)["version"] == info["CFBundleShortVersionString"]
' "$APP_PATH/Contents/Info.plist"
echo "中文版身份、双架构、签名与无设备入口检查通过"
