#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_app="${1:-$repo_dir/dist/ChromeTranslateHotkey.app}"
target_app="/Applications/ChromeTranslateHotkey.app"
label="com.ray.chrometranslatehotkey"
domain="gui/$(id -u)"
launch_plist="$HOME/Library/LaunchAgents/$label.plist"
backup_dir="$HOME/Library/Application Support/RayTools/ChromeTranslateHotkey/backups/install-$(date +%Y%m%d_%H%M%S)-$$"
test -f "$source_app/Contents/MacOS/ChromeTranslateHotkey"
codesign --verify --strict "$source_app"
# Stage the complete bundle before stopping the current service.
stage_dir="$(mktemp -d /Applications/.ChromeTranslateHotkey.XXXXXX)"
trap 'rm -rf "$stage_dir"' EXIT
ditto "$source_app" "$stage_dir/ChromeTranslateHotkey.app"
codesign --verify --strict "$stage_dir/ChromeTranslateHotkey.app"
mkdir -p "$backup_dir" "$(dirname "$launch_plist")"
if [ -d "$target_app" ]; then ditto "$target_app" "$backup_dir/ChromeTranslateHotkey.app"; fi
if [ -f "$launch_plist" ]; then cp "$launch_plist" "$backup_dir/$label.plist"; fi
launchctl bootout "$domain/$label" 2>/dev/null || true
if [ -d "$target_app" ]; then mv "$target_app" "$stage_dir/previous.app"; fi
mv "$stage_dir/ChromeTranslateHotkey.app" "$target_app"
cat > "$launch_plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.ray.chrometranslatehotkey</string>
<key>ProgramArguments</key><array><string>/Applications/ChromeTranslateHotkey.app/Contents/MacOS/ChromeTranslateHotkey</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
if ! launchctl bootstrap "$domain" "$launch_plist"; then
  echo "LaunchAgent failed. Restoring the previous installation." >&2
  mv "$target_app" "$stage_dir/failed.app"
  if [ -d "$stage_dir/previous.app" ]; then mv "$stage_dir/previous.app" "$target_app"; fi
  if [ -f "$backup_dir/$label.plist" ]; then
    cp "$backup_dir/$label.plist" "$launch_plist"
    launchctl bootstrap "$domain" "$launch_plist" || true
  else
    rm -f "$launch_plist"
  fi
  exit 1
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target_app"
touch "$target_app"
printf 'Installed: %s\nBackup: %s\n' "$target_app" "$backup_dir"
echo "请在系统设置 → 隐私与安全性 → 辅助功能中添加并开启新 App；旧同名权限项可能需要先移除。"
