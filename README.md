# nvim-macos

My reproducible, learning-friendly Neovim setup for macOS, based on
[LazyVim](https://www.lazyvim.org/) with every plugin commit locked.

It includes **Dojo**: Neovim as a calm desktop editor. You open it like VS Code
or Sublime Text, it uses the Cmd shortcuts you already know, and it teaches you
the Vim way to do each thing as you go.

## Dojo in one minute

- **Open it** from Spotlight ("Dojo"), the Dock, or a terminal. `dojo ~/code/app`
  (or `v .` in zsh) opens a folder as the project. You can also drop a folder
  onto the Dojo icon.
- **The window opens centred** on the screen under your mouse, at a calm 3:2
  proportion. With several Dojo windows open (⌘N), `dojo` and `v` talk to
  the first one.
- **Open a folder** with ⌘O, the native macOS picker, or ⌘⌥O for recent
  projects. Each project reopens where you left it: its files, splits and
  cursor.
- **See every shortcut** with ⌘K ⌘S (or `Space ?`). The sheet shows the macOS
  chord, what it does, and the Vim way. Press Enter on a row to run it.
- **Search everything** with ⌘⇧P, the command palette. Every row shows its
  shortcut, so the palette slowly teaches you not to need it.

| You want to… | Press | The Vim way |
| --- | --- | --- |
| Find a file | ⌘P | `Space Space` |
| Search in this file / whole project | ⌘F / ⌘⇧F | `/text` / `Space /` |
| Go to definition / references | F12 (or ⌘-click) / ⇧F12 | `gd` / `gr` |
| Rename a symbol · quick fix | F2 · ⌘. | `Space c r` · `Space c a` |
| Toggle the file explorer | ⌘B | `Space e` |
| Run this file · terminal panel | ⌘R · ⌃` | `Space r r` · `Ctrl-/` |
| Comment · multi-cursor | ⌘/ · ⌘D | `gcc` · `Ctrl-n` |
| Move / duplicate a line | ⌥↑↓ / ⇧⌥↑↓ | `Alt-k/j` · `yyp` |
| Zen mode (a calm, centred page) | ⌘K Z | `Space u z` |
| Ask the Tutor · Claude Code | ⌘I · ⌘L | `Space t a` · `Space a c` |

Neovide's own menu keeps ⌘N (new window), ⌘H, ⌘M, ⌘Q and ⌃⌘F.

### Learning

The cheatsheet's **Learn** tab and `:DojoLearn` gather everything in one place:

- `:VimTutor`: Vim's own interactive 30-minute lesson.
- Practice games: `:VimBeGood` for motions, `:Typr` for typing.
- Training wheels, each off by default:
  - motion hints showing where `w b e ^ $` would land (`Space u P`)
  - on-screen keys (`Space u K`)
  - gentle habit hints, for example "try `5j` instead of `jjjjj`" (`Space u H`,
    and `:Hardtime report`)
- The statusline shows the current mode, and the cursor line takes the mode's
  colour.
- The dashboard teaches one Vim command per day.

### Look, feel and sound

- **Type:** Monaspace Neon (the Nerd Font build, "Monaspice") at 15 pt with
  ~1.4 line height. Texture healing is on; symbol ligatures are off, so you
  always see the real characters.
- **Colour:** Catppuccin, Mocha when macOS is dark and a readability-tuned Latte
  when it is light. It switches automatically; don't pick a flavour-specific
  name if you want that.
- **Calm by default:** no italics in code, an instant cursor (no glide or
  trail), borderless floating cards with soft shadows, and quiet panel titles.
  `Space u V` adds a subtle cursor trail if you want one.
- **Wide screens:** ⌘K Z gives a calm, centred page. Long lines soft-wrap with
  their indent kept; nothing hard-wraps while you type. Rulers sit at each
  formatter's line length.
- **Sound:** a soft mechanical "thock" while typing and a quiet bell on save and
  run. Toggle with ⌘K M or `Space u M`; `NVIM_SFX=0` disables it. A tiny
  Swift daemon (`sfx/`) plays the sounds with ~12 ms latency. It builds itself
  on first launch with `swiftc` and mutes when the window loses focus.

### Terminal (Ghostty)

`extras/ghostty/config` gives Ghostty the same font and theme. Cmd keys reach
Neovim too, through the kitty keyboard protocol, so the table above also works
in `nvim` inside Ghostty. The exceptions are ⌘F, ⌘D, ⌘W, ⌘T and ⌘N, which stay
Ghostty's own; use `/` to search. ⌘← / ⌘→ keep their shell meaning (use
Home / End in terminal nvim). Don't run nvim inside tmux if you want Cmd
keys.

## Install on a fresh Mac

One command:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/yask123/nvim-macos/main/install.sh)"
```

The first run may ask for Apple Command Line Tools or Homebrew permissions.
Rerun the same command after completing an Apple system prompt.

For the Dojo desktop pieces, run this once after installing. It links the
Neovide and Ghostty configs (never overwriting existing ones), adds the zsh
helpers, and builds `~/Applications/Dojo.app`:

```bash
~/.config/nvim/scripts/setup-dojo.sh
```

The installer:

- installs Neovim, Git, search tools, Node, Python, Lua, and the matching fonts;
- moves any existing Neovim config, plugins, state, and cache to a timestamped
  unique backup under `~/.local/state/nvim-bootstrap/backups/`;
- clones this repository to `~/.config/nvim`;
- restores the exact plugin commits in `lazy-lock.json`;
- installs the configured LSP servers and formatters through Mason;
- installs `nvim-update` in `~/.local/bin` for safe future updates;
- runs a non-destructive doctor at the end.

It does not copy credentials, Claude authentication, note contents, sessions,
undo history, shell configuration, or terminal preferences.

### Inspect before running

```bash
git clone https://github.com/yask123/nvim-macos.git
cd nvim-macos
less install.sh
./install.sh
```

When run from this checkout, the installer uses its committed contents. This
makes the inspected route match what gets installed.

Useful installer switches:

```bash
./install.sh --skip-brew      # Brewfile dependencies and fonts already exist
./install.sh --skip-plugins   # clone only; install plugins on first launch
./install.sh --no-app         # terminal only: skip the Dojo app setup
```

Re-running the installer is safe: the current Neovim directories are moved to
a unique backup before a clean copy is installed. Existing shared Homebrew
packages are not upgraded during the bootstrap.

## What is configured

- Python: basedpyright, Ruff, Black, virtual-environment selection
- TypeScript/JavaScript: vtsls, Prettier, path-safe file runner
- JSON and Lua language support
- Blink completion (Tab or Enter accepts), Snacks picker and explorer, Lazygit
- Obsidian-style Markdown notes rooted at `~/notes` (maintained
  `obsidian-nvim` fork)
- rendered Markdown, breadcrumbs, sticky context, and several light/dark themes
- Claude Code integration when the separate `claude` command is installed
- a read-only OpenAI Tutor for questions about selected text or the current file
- debounced auto-save for normal named files only
- a focused learning view with quiet diagnostics (errors only, no inline text)
  and minimal chrome

### Learning Tutor

Tutor is for understanding code, not generating or editing it. Select text and
press `Space t a`, or press the same keys in normal mode to ask about the whole
file. A compact chat opens on the right, or below in a narrow terminal; ask
follow-ups with `a` or `Enter`.

Tutor uses OpenAI's Responses API and reads the key only from your environment:

```bash
export OPENAI_API_KEY="your-key"
```

Put that line in `~/.zshrc`, then open a new terminal before starting Neovim.
Do not put the key in this repository. `:TutorHealth` checks the local
prerequisites without showing the key; it does not make a request or validate
API access. OpenAI API usage is [billed separately from
ChatGPT](https://help.openai.com/en/articles/8156019). The default model is
`gpt-5.6-sol`; `NVIM_TUTOR_MODEL` may override it with a compatible GPT-5.6
model.

The selected text or current-file snapshot is sent only when you ask. Each
follow-up also sends recent chat turns. The local transcript stays in Neovim
memory, requests use `store: false`, and Tutor has no tools that can modify the
source buffer. OpenAI's separate [API data-control
policy](https://platform.openai.com/docs/models/default-usage-policies-by-endpoint)
still applies. Contexts over 60,000 characters are not sent; select the
relevant lines instead.

### Main custom keys

Leader is the space bar. The full, searchable list is in the app itself
(⌘K ⌘S or `Space ?`); these are the extra keys from before Dojo:

| Key | Action |
| --- | --- |
| `Space r r` | Save and run the current Python, JS/TS, Lua, shell, Go, or Rust file |
| `Space r c` | Run again with fresh output |
| `Space r q` | Close the output panel |
| `Space r i` | Open a Python REPL |
| `Space z l` | Toggle the focused learning view |
| `Space e` | Toggle the file explorer |
| `Ctrl+\` | Toggle a floating terminal |
| `Ctrl+W` | Close the current buffer (intentional VS Code-style override) |
| `Tab` / `Shift+Tab` | Next / previous buffer |
| `Ctrl+A` / `Ctrl+E` | Line start / end (as in every Mac text field; select all is ⌘A) |
| `Ctrl+N` | Add a cursor at the next match (multicursor.nvim; `Esc` clears) |
| `Space u C` | Choose and remember a colorscheme |
| `Space n H` | Notes menu |
| `Space t a` | Ask Tutor about the selection or current file |
| `Space t t` | Toggle the Tutor sidebar |
| `Space a c` | Toggle Claude Code, when installed |

Inside Tutor: `a` or `Enter` asks a follow-up, `n` starts a new chat, `x`
stops the current answer, and `q` closes the sidebar.

All normal LazyVim keys remain available except where explicitly overridden.

The run command uses argument arrays rather than a shell string, so filenames
with spaces or shell punctuation are handled safely. TypeScript uses
`npx --yes tsx@4.19.3` and may download that pinned version on first use. Go
and Rust runners additionally require `go` and `cargo`.

## Check or develop the setup

```bash
~/.config/nvim/scripts/doctor.sh
~/.config/nvim/scripts/doctor.sh --strict  # include optional tools
make format-check
make test
```

`make test` creates isolated temporary XDG directories, restores the pinned
plugins there, checks the runner and Ruff behavior, and verifies that the test
did not mutate the source repository. It also exercises backup-first install
and recoverable uninstall behavior in a temporary home directory.

To apply repository changes on this or another installed Mac without replacing
local state, quit Neovim and run:

```bash
nvim-update
```

The command fast-forwards the tracked Git branch, refuses to overwrite local
config changes, restores the plugin commits pinned in `lazy-lock.json`, installs
the configured editor tools, and runs the doctor. If `~/.local/bin` is not in
your shell's `PATH`, run `~/.local/bin/nvim-update` or add that directory to
`PATH`. Use `nvim-update --skip-plugins` when you only want the config files.

Use `:Lazy update` only when intentionally refreshing plugin versions, then
review and commit the resulting `lazy-lock.json`.

## Reproducibility boundary

Plugin commits are pinned. Homebrew formulae and Mason packages install their
current compatible releases, so system tools can move forward over time. The
doctor and CI smoke test catch compatibility drift. The minimum supported
editor is Neovim 0.11.2 with LuaJIT; the setup is tested on 0.11.5 and 0.12.5.
On 0.11 nvim-treesitter stays pinned to its last compatible commit.

Plugin restores run twice (`scripts/restore-plugins.sh`). lazy.nvim resolves
LazyVim's own plugins only after LazyVim itself is installed, and rewrites the
lockfile in between. A single restore therefore left those plugins at upstream
HEAD. This boundary is intentionally more
maintainable than committing machine binaries or personal authentication.

## Remove or restore

The uninstall is recoverable and does not remove shared Homebrew packages:

```bash
~/.config/nvim/scripts/uninstall.sh
```

It moves the four Neovim directories to
`~/.local/state/nvim-bootstrap/uninstalled/<timestamp>.<unique>/`. Installer
backups use the same `config`, `data`, `state`, and `cache` labels, so individual
directories can be moved back to their original XDG locations if needed.

## License

Apache-2.0. See [LICENSE](LICENSE).
