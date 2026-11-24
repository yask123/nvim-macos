#!/usr/bin/env bash
# Build ~/Applications/Code.app: the editor as a Mac app of its own. It is a
# copy of Neovide with its own name, icon and identifier, so the menu bar says
# "Code" (About Code, Quit Code), and so do ⌘Tab, the Dock and Activity
# Monitor. Also links the `code` and `dojo` commands. Safe to re-run (nvim-update does, so
# a newer Neovide or a new icon is picked up).
#
# The app was called Dojo until November 2026; the code, the `dojo` command
# and the bundle identifier keep that name. An old Dojo.app is removed here.

set -Eeuo pipefail

config_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="${DOJO_APP_DIR:-$HOME/Applications}"
app_name="Code" # what the Mac calls it: the Dock, the menu bar, Spotlight, ⌘Tab
app="$app_dir/$app_name.app"
neovide_app="${DOJO_NEOVIDE_APP:-/Applications/Neovide.app}"
bundle_id="dev.dojo.editor"
pb=/usr/libexec/PlistBuddy

mkdir -p "$HOME/.local/bin" "$app_dir"
# The terminal command, under both names: `code .` like VS Code's, and `dojo`
# (the name that is never taken by something else).
"$config_dir/scripts/link-cli.sh"

if [[ ! -x "$neovide_app/Contents/MacOS/neovide" ]]; then
  printf 'Neovide is not installed at %s (brew install --cask neovide-app)\n' "$neovide_app" >&2
  exit 1
fi
# Ours: built by this script (dev.dojo.launcher was the first, launcher-only app).
ours() {
  case "$("$pb" -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null)" in
    "$bundle_id" | dev.dojo.launcher) return 0 ;;
    *) return 1 ;;
  esac
}
if [[ -d "$app" ]] && ! ours "$app"; then
  printf 'Refusing to replace %s: it is a different app\n' "$app" >&2
  exit 1
fi

# Build next to the target, then swap it in.
staging="$app_dir/.$app_name.app.building"
rm -rf -- "$staging"
ditto "$neovide_app" "$staging"
mv "$staging/Contents/MacOS/neovide" "$staging/Contents/MacOS/$app_name"

sp="$staging/Contents/Info.plist"
set_key() { # key type value
  "$pb" -c "Set :$1 $3" "$sp" 2>/dev/null || "$pb" -c "Add :$1 $2 $3" "$sp"
}
set_key CFBundleExecutable string "$app_name"
set_key CFBundleName string "$app_name"
set_key CFBundleDisplayName string "$app_name"
set_key CFBundleIdentifier string "$bundle_id"
set_key NSHumanReadableCopyright string "$app_name, built on Neovide and Neovim"

# The icon file is named after its content hash: launchers that cache icons by
# name (Raycast, Alfred) then pick up a new icon as soon as it changes.
icon_name="$app_name-$(shasum "$config_dir/extras/dojo/$app_name.icns" | cut -c1-8)"
cp "$config_dir/extras/dojo/$app_name.icns" "$staging/Contents/Resources/$icon_name.icns"
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

# ⌘N is New File, as in every editor; a new window is ⌘⇧N. Neovide's menu
# binds New Window to ⌘N and offers no setting, so use the Mac's own way of
# rebinding a menu item: the app's NSUserKeyEquivalents (what System Settings ›
# Keyboard › App Shortcuts writes). "@" is ⌘, "$" is ⇧.
if [[ -z "${DOJO_SKIP_REGISTER:-}" ]]; then
  # shellcheck disable=SC2016 # '@$n' is the literal key code for ⌘⇧N
  defaults write "$bundle_id" NSUserKeyEquivalents -dict-add "New Window" '@$n' >/dev/null 2>&1 || true
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
# Tell Spotlight and the Dock about it (DOJO_SKIP_REGISTER: a test build).
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
register() {
  [[ -n "${DOJO_SKIP_REGISTER:-}" ]] || "$lsregister" "$@" >/dev/null 2>&1 || true
}
register -f "$app"

printf 'Built %s — find it with Spotlight ("%s") or drag it to the Dock.\n' "$app" "$app_name"

# The app's earlier name: retire that copy, but never under a window that is open.
old="$app_dir/Dojo.app"
if [[ -d "$old" ]] && ours "$old"; then
  if pgrep -qf -- "$old/Contents/MacOS/"; then
    printf 'Dojo.app (the old name) is still open. Quit it, then run this again to remove it.\n'
  else
    register -u "$old"
    rm -rf -- "$old"
    printf 'Removed %s (the old name)\n' "$old"
  fi
fi
