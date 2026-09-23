#!/usr/bin/env bash
# Build ~/Applications/Dojo.app: Dojo as a Mac app of its own. It is a copy of
# Neovide with Dojo's name, icon and identifier, so the menu bar says "Dojo"
# (About Dojo, Quit Dojo), and so do ⌘Tab, the Dock and Activity Monitor.
# Also links the `dojo` command. Safe to re-run (nvim-update does, so a newer
# Neovide or a new icon is picked up).

set -Eeuo pipefail

config_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="${DOJO_APP_DIR:-$HOME/Applications}"
app="$app_dir/Dojo.app"
neovide_app="${DOJO_NEOVIDE_APP:-/Applications/Neovide.app}"
bundle_id="dev.dojo.editor"
plist="$app/Contents/Info.plist"
pb=/usr/libexec/PlistBuddy

mkdir -p "$HOME/.local/bin" "$app_dir"
bin="$HOME/.local/bin/dojo"
if [[ -e "$bin" && ! -L "$bin" ]] || { [[ -L "$bin" ]] && [[ "$(realpath "$bin")" != "$(realpath "$config_dir/scripts/dojo")" ]]; }; then
  printf 'Skipping %s: it is not this repo'"'"'s dojo script\n' "$bin"
else
  ln -sf "$config_dir/scripts/dojo" "$bin"
fi

if [[ ! -x "$neovide_app/Contents/MacOS/neovide" ]]; then
  printf 'Neovide is not installed at %s (brew install --cask neovide-app)\n' "$neovide_app" >&2
  exit 1
fi
if [[ -d "$app" ]]; then
  case "$("$pb" -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null)" in
    "$bundle_id" | dev.dojo.launcher) ;; # ours (dev.dojo.launcher: the old launcher)
    *)
      printf 'Refusing to replace %s: it is a different app\n' "$app" >&2
      exit 1
      ;;
  esac
fi

# Build next to the target, then swap it in.
staging="$app_dir/.Dojo.app.building"
rm -rf -- "$staging"
ditto "$neovide_app" "$staging"
mv "$staging/Contents/MacOS/neovide" "$staging/Contents/MacOS/Dojo"

sp="$staging/Contents/Info.plist"
set_key() { # key type value
  "$pb" -c "Set :$1 $3" "$sp" 2>/dev/null || "$pb" -c "Add :$1 $2 $3" "$sp"
}
set_key CFBundleExecutable string Dojo
set_key CFBundleName string Dojo
set_key CFBundleDisplayName string Dojo
set_key CFBundleIdentifier string "$bundle_id"
set_key NSHumanReadableCopyright string "Dojo, built on Neovide and Neovim"

# The icon file is named after its content hash: launchers that cache icons by
# name (Raycast, Alfred) then pick up a new icon as soon as it changes.
icon_name="Dojo-$(shasum "$config_dir/extras/dojo/Dojo.icns" | cut -c1-8)"
cp "$config_dir/extras/dojo/Dojo.icns" "$staging/Contents/Resources/$icon_name.icns"
rm -f "$staging/Contents/Resources/Assets.car"
"$pb" -c "Delete :CFBundleIconName" "$sp" 2>/dev/null || true
set_key CFBundleIconFile string "$icon_name"

# Where nvim lives, so Neovide finds it even if a login shell can't.
nvim_bin="$(command -v nvim || true)"
for candidate in /opt/homebrew/bin/nvim /usr/local/bin/nvim; do
  [[ -n "$nvim_bin" ]] && break
  [[ -x "$candidate" ]] && nvim_bin="$candidate"
done
"$pb" -c "Delete :LSEnvironment" "$sp" 2>/dev/null || true
if [[ -n "$nvim_bin" ]]; then
  "$pb" -c "Add :LSEnvironment dict" -c "Add :LSEnvironment:NEOVIM_BIN string $nvim_bin" "$sp"
fi

# Folders can be dropped on the icon too (they open as the project).
"$pb" -c "Add :CFBundleDocumentTypes:0 dict" \
  -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Folder" \
  -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Editor" \
  -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" \
  -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string public.folder" "$sp"

codesign --force --deep --sign - "$staging" >/dev/null 2>&1
rm -rf -- "$app"
mv "$staging" "$app"
touch "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" >/dev/null 2>&1 || true

printf 'Built %s — find it with Spotlight ("Dojo") or drag it to the Dock.\n' "$app"
