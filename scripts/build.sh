#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_arch="${BUILD_ARCH:-$(uname -m)}"
case "$build_arch" in x86_64|arm64) ;; *) echo "Unsupported architecture: $build_arch" >&2; exit 1 ;; esac
mkdir -p "$repo_dir/build" "$repo_dir/dist"
stage_dir="$(mktemp -d "$repo_dir/build/package.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
app_dir="$stage_dir/ChromeTranslateHotkey.app"
iconset_dir="$stage_dir/AppIcon.iconset"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$iconset_dir"
cp "$repo_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
xcrun swiftc -O -target "$build_arch-apple-macosx15.0" "$repo_dir/Sources/ChromeTranslateHotkey.swift" -o "$app_dir/Contents/MacOS/ChromeTranslateHotkey"
while read -r pixels icon_name; do
  sips -z "$pixels" "$pixels" "$repo_dir/Resources/AppIcon.png" --out "$iconset_dir/$icon_name" >/dev/null
done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"
plutil -lint "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
# dist contains only generated outputs.
rm -rf "$repo_dir/dist/ChromeTranslateHotkey.app"
ditto "$app_dir" "$repo_dir/dist/ChromeTranslateHotkey.app"
zip_path="$repo_dir/dist/ChromeTranslateHotkey-1.1-macos-$build_arch.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$zip_path"
(cd "$(dirname "$zip_path")" && shasum -a 256 "$(basename "$zip_path")") > "$zip_path.sha256"
printf 'Built: %s\n' "$zip_path"
