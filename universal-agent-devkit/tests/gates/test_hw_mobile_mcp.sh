#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh with the mobile-mcp tools (@mobilenext/mobile-mcp 1.0.16, replaces replicant-mcp, 08/11/2026).
# Tool names and parameters are read from the package source (lib/server.js): every tool but get_more_tools is
# mcp__mobile-mcp__mobile_<name>; the device is the string parameter `device` (a serial, or the AVD NAME on an emulator).
# mobile_batch_commands runs other tools as steps: a step's own `device` replaces the batch device, listElementsAtEnd lists the
# screen of the BATCH device, and the four cloud tools are batchable. The hook must see all of it (plan_review T0001).
# Only runs the hook, never a command or a device. Compatible with bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
. "$DEVKIT_DIR/tests/lib/guard_shell_norm_lib.sh"   # TMP, repo nháp $P, ok / fail / crashed

# mm <want rc> <tool name without prefix> <tool_input json>: DENIED1 is on the device denylist, nothing else is.
mm() {
  local want="$1" name="$2" inp="$3" tool="mcp__mobile-mcp__$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[3],"hook_event_name":"PreToolUse",
    "tool_name":sys.argv[1],"tool_input":json.loads(sys.argv[2])}))' "$tool" "$inp" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" XDG_CONFIG_HOME="$TMP/xdg" ADB_DENY_SERIALS=DENIED1 ADB_ALLOW_SERIALS= ANDROID_SERIAL= \
      bash "$HW" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ] && ! crashed; then ok "mm rc $rc: $name $inp"; else fail "mm rc $rc (want $want): $name $inp — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; fi
}

echo "── mobile-mcp: device policy by the device parameter"
mm 2 mobile_clear_app_data '{"device":"DENIED1","packageName":"com.example.app"}'
mm 0 mobile_clear_app_data '{"device":"OK1","packageName":"com.example.app"}'
mm 2 mobile_install_app '{"device":"DENIED1","path":"/tmp/a.apk"}'
mm 0 mobile_install_app '{"device":"OK1","path":"/tmp/a.apk"}'
mm 2 mobile_uninstall_app '{"device":"DENIED1","packageName":"com.example.app"}'
mm 0 mobile_uninstall_app '{"device":"OK1","packageName":"com.example.app"}'
mm 2 mobile_list_elements_on_screen '{"device":"DENIED1"}'
mm 0 mobile_list_elements_on_screen '{"device":"OK1"}'
mm 2 mobile_set_location '{"device":"DENIED1","latitude":1,"longitude":2}'
mm 2 mobile_clipboard '{"device":"DENIED1","text":"x"}'
mm 2 mobile_open_url '{"device":"DENIED1","url":"https://example.com"}'
mm 0 mobile_list_available_devices '{}'
mm 0 get_more_tools '{}'

echo "── mobile-mcp: a call that names no device cannot be judged"
mm 2 mobile_clear_app_data '{"packageName":"com.example.app"}'
mm 2 mobile_click_on_screen_at_coordinates '{"device":"","x":1,"y":2}'

echo "── mobile-mcp: removing a system app is refused whatever the device is called"
mm 2 mobile_uninstall_app '{"device":"OK1","packageName":"com.android.systemui"}'
mm 2 mobile_uninstall_app '{"device":"Pixel 7 API 34","packageName":"com.android.systemui"}'
mm 2 mobile_uninstall_app '{"device":"Toan'"'"'s Pixel 8","packageName":"com.android.systemui"}'
mm 0 mobile_uninstall_app '{"device":"Pixel 7 API 34","packageName":"com.example.app"}'

echo "── mobile-mcp: cloud tools are refused by default"
mm 2 mobile_login_to_cloud_provider '{}'
mm 2 mobile_list_remote_devices '{}'
mm 2 mobile_allocate_remote_device '{}'
mm 2 mobile_release_remote_device '{"device":"OK1"}'

echo "── mobile-mcp: mobile_batch_commands does not get around the guard"
mm 0 mobile_batch_commands '{"device":"OK1","steps":[{"name":"mobile_click_on_screen_at_coordinates","arguments":{"x":1,"y":2}},{"name":"mobile_type_keys","arguments":{"text":"a","submit":false}}]}'
mm 2 mobile_batch_commands '{"device":"DENIED1","steps":[{"name":"mobile_type_keys","arguments":{"text":"a"}}]}'
mm 2 mobile_batch_commands '{"device":"OK1","steps":[{"name":"mobile_type_keys","arguments":{"device":"DENIED1","text":"a"}}]}'
mm 2 mobile_batch_commands '{"device":"OK1","steps":[{"name":"mobile_clear_app_data","arguments":{"device":"DENIED1","packageName":"com.example.app"}}]}'
mm 2 mobile_batch_commands '{"device":"OK1","steps":[{"name":"mobile_login_to_cloud_provider","arguments":{}}]}'
mm 2 mobile_batch_commands '{"device":"OK1","steps":[{"name":"mobile_allocate_remote_device","arguments":{}}]}'
mm 2 mobile_batch_commands '{"device":"DENIED1","steps":[{"name":"mobile_type_keys","arguments":{"device":"OK1","text":"a"}}],"listElementsAtEnd":true}'
mm 2 mobile_batch_commands '{"device":"OK1","steps":[{"name":"mobile_uninstall_app","arguments":{"packageName":"com.android.systemui"}}]}'
mm 2 mobile_batch_commands '{"device":"OK1","steps":[]}'
mm 2 mobile_batch_commands '{"device":"OK1"}'
mm 2 mobile_batch_commands '{"device":"OK1","steps":"x"}'
mm 2 mobile_batch_commands '{"steps":[{"name":"mobile_type_keys","arguments":{"text":"a"}}]}'

echo "── mobile-mcp: a step whose arguments are not an object cannot be read"
mm 2 mobile_batch_commands '{"device":"OK1","steps":[{"name":"mobile_uninstall_app","arguments":"x"}]}'
mm 2 mobile_batch_commands '{"device":"OK1","steps":[{"name":"mobile_uninstall_app"}]}'
mm 2 mobile_batch_commands '{"device":"OK1","steps":["x"]}'

mm 2 mobile_batch_commands '{"device":"OK1","steps":[{"name":"mobile_type_keys","arguments":{"device":null,"text":"a"}}]}'
mm 2 mobile_batch_commands '{"device":"OK1","steps":[{"name":"mobile_type_keys","arguments":{"device":7,"text":"a"}}]}'

echo "── mobile-mcp: extra keys that look like a Bash payload do not open the fast path (audit 09/11)"
mm 2 mobile_clear_app_data '{"device":"DENIED1","packageName":"com.example.app","tool_name":"Bash","command":"ls"}'
mm 2 mobile_batch_commands '{"device":"OK1","steps":[{"name":"mobile_login_to_cloud_provider","arguments":{"tool_name":"Bash","command":"ls"}}]}'
mm 2 mobile_uninstall_app '{"device":"OK1","packageName":"com.android.systemui","toolName":"Bash","command":"ls"}'

# mmf <want rc> <file> <name> <json>: the device policy comes from <repo>/.adb-<file> (a device name with spaces is ONE entry there)
mmf() {
  local want="$1" file="$2" name="$3" inp="$4" tool="mcp__mobile-mcp__$3"
  printf '%s\n' "$5" > "$P/.adb-$file"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[3],"hook_event_name":"PreToolUse",
    "tool_name":sys.argv[1],"tool_input":json.loads(sys.argv[2])}))' "$tool" "$inp" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" XDG_CONFIG_HOME="$TMP/xdg" ADB_DENY_SERIALS= ADB_ALLOW_SERIALS= ANDROID_SERIAL= \
      bash "$HW" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  rm -f "$P/.adb-$file"
  if [ "$rc" = "$want" ] && ! crashed; then ok "mmf $file rc $rc: $name $inp"; else fail "mmf $file rc $rc (want $want): $name $inp — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; fi
}
echo "── mobile-mcp: device names with spaces in .adb-denylist / .adb-allowlist (audit 09/11)"
mmf 2 denylist mobile_clear_app_data '{"device":"Toan'"'"'s Pixel 8","packageName":"com.example.app"}' "Toan's Pixel 8   # my phone"
mmf 2 denylist mobile_clear_app_data '{"device":"Pixel 7 API 34","packageName":"com.example.app"}' "Pixel 7 API 34"
mmf 0 denylist mobile_clear_app_data '{"device":"Pixel 7 API 35","packageName":"com.example.app"}' "Pixel 7 API 34"
mmf 0 allowlist mobile_list_elements_on_screen '{"device":"Pixel 7 API 34"}' "Pixel 7 API 34"
mmf 2 allowlist mobile_list_elements_on_screen '{"device":"Pixel 9 API 34"}' "Pixel 7 API 34"
mmf 2 denylist mobile_clear_app_data '{"device":"DENIED1","packageName":"com.example.app"}' "DENIED1 OTHER1"
# an allowlist entry is the whole line: its words do not allow other devices (review 09/11: "API" passed with "Pixel 7 API 34")
mmf 2 allowlist mobile_list_elements_on_screen '{"device":"API"}' "Pixel 7 API 34"
mmf 2 allowlist mobile_list_elements_on_screen '{"device":"Pixel"}' "Pixel 7 API 34"
mmf 0 allowlist mobile_list_elements_on_screen '{"device":"Toan'"'"'s Pixel 8"}' "Toan's Pixel 8  # my phone"
mmf 2 allowlist mobile_list_elements_on_screen '{"device":"8"}' "Toan's Pixel 8"
mmf 0 allowlist mobile_list_elements_on_screen '{"device":"emulator-5554"}' "emulator-5554,Pixel 7 API 34"
mmf 0 allowlist mobile_list_elements_on_screen '{"device":"Pixel 7 API 34"}' "emulator-5554,Pixel 7 API 34"
mmf 2 allowlist mobile_list_elements_on_screen '{"device":"API"}' "emulator-5554,Pixel 7 API 34"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
