#!/usr/bin/env bash
# Build ~/Applications/Dojo.app: a tiny launcher for Spotlight, the Dock and
# Finder. Clicking it runs `dojo`; dropping a folder or file on it opens that.
# It carries the Dojo icon and quits right away (Neovide is the editor window).

set -Eeuo pipefail

config_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="${DOJO_APP_DIR:-$HOME/Applications}"
app="$app_dir/Dojo.app"
work="$(mktemp -d "${TMPDIR:-/tmp}/dojo-app.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

mkdir -p "$HOME/.local/bin" "$app_dir"
bin="$HOME/.local/bin/dojo"
if [[ -e "$bin" && ! -L "$bin" ]] || { [[ -L "$bin" ]] && [[ "$(realpath "$bin")" != "$(realpath "$config_dir/scripts/dojo")" ]]; }; then
  printf 'Skipping %s: it is not this repo'"'"'s dojo script\n' "$bin"
else
  ln -sf "$config_dir/scripts/dojo" "$bin"
fi
if [[ -d "$app" ]] && [[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null)" != "dev.dojo.launcher" ]]; then
  printf 'Refusing to replace %s: it is a different app\n' "$app" >&2
  exit 1
fi

cat >"$work/Dojo.applescript" <<'EOF'
on run
	do shell script "\"$HOME/.local/bin/dojo\" > /dev/null 2>&1 &"
end run

on open theItems
	repeat with anItem in theItems
		do shell script "\"$HOME/.local/bin/dojo\" " & quoted form of (POSIX path of anItem) & " > /dev/null 2>&1 &"
	end repeat
end open
EOF

rm -rf -- "$app"
osacompile -o "$app" "$work/Dojo.applescript"

plist="$app/Contents/Info.plist"
cp "$config_dir/extras/dojo/Dojo.icns" "$app/Contents/Resources/droplet.icns"
rm -f "$app/Contents/Resources/Assets.car"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile droplet" "$plist" 2>/dev/null ||
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string droplet" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string dev.dojo.launcher" "$plist" 2>/dev/null ||
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.dojo.launcher" "$plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$plist" 2>/dev/null ||
  /usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$plist"
# Accept folders and any file dropped on the icon.
/usr/libexec/PlistBuddy -c "Delete :CFBundleDocumentTypes" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy \
  -c "Add :CFBundleDocumentTypes array" \
  -c "Add :CFBundleDocumentTypes:0 dict" \
  -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" \
  -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" \
  -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string public.folder" \
  -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:1 string public.item" \
  "$plist"

codesign --force --deep --sign - "$app" >/dev/null 2>&1
touch "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" >/dev/null 2>&1 || true

printf 'Built %s — find it with Spotlight ("Dojo") or drag it to the Dock.\n' "$app"
