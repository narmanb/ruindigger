#!/usr/bin/env bash
# Writes the Godot editor settings the Android exporter needs.
# usage: configure_android_editor.sh <android_sdk> <java_home> <debug_keystore> [user] [pass]
set -euo pipefail
SDK="$1"; JAVA="$2"; KS="$3"; USER_="${4:-androiddebugkey}"; PASS="${5:-android}"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
mkdir -p "$CFG"
cat > "$CFG/editor_settings-4.6.tres" <<TRES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$SDK"
export/android/java_sdk_path = "$JAVA"
export/android/debug_keystore = "$KS"
export/android/debug_keystore_user = "$USER_"
export/android/debug_keystore_pass = "$PASS"
TRES
echo "wrote $CFG/editor_settings-4.6.tres"
