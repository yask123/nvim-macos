-- Neovide-only settings (the Dojo app). Fonts live in extras/neovide/config.toml;
-- never set 'guifont' here, it would replace the per-style font families.

local M = {}

function M.setup()
  if not vim.g.neovide then
    return
  end
  local g = vim.g

  -- Neovide animates scrolling itself; don't stack snacks.scroll on top.
  g.snacks_scroll = false

  -- Type rhythm: ~1.4 line height with Monaspace at 15pt (linespace is in physical px).
  vim.opt.linespace = 4

  -- Breathing room around the text (physical px; the transparent titlebar adds its own top inset).
  g.neovide_padding_top = 6
  g.neovide_padding_bottom = 12
  g.neovide_padding_left = 36
  g.neovide_padding_right = 36

  -- Follow macOS light/dark for the window chrome; 'background' follows it automatically.
  g.neovide_theme = "auto"
  g.neovide_opacity = 1.0
  g.neovide_hide_mouse_when_typing = true
  g.neovide_input_macos_option_key_is_meta = "only_left" -- ⌥ works as Alt (move line ⌥↑/⌥↓)

  -- Floating windows: soft shadows, gentle rounding.
  g.neovide_floating_shadow = true
  g.neovide_floating_z_height = 8
  g.neovide_light_angle_degrees = 40
  g.neovide_light_radius = 6
  g.neovide_floating_corner_radius = 0.15

  -- Motion: instant, like a native editor (no glide, no trail, no smooth scroll).
  g.neovide_position_animation_length = 0.0
  g.neovide_scroll_animation_length = 0.0
  g.neovide_scroll_animation_far_lines = 1
  g.neovide_cursor_animation_length = 0.0
  g.neovide_cursor_short_animation_length = 0.0
  g.neovide_cursor_trail_size = 0.0
  g.neovide_cursor_animate_in_insert_mode = false
  g.neovide_cursor_animate_command_line = false
  g.neovide_cursor_smooth_blink = false -- smooth blink forces constant redraws
  g.neovide_cursor_antialiasing = true

  -- Cursor particles are off; `Space u V` turns a subtle trail on for fun.
  M.vfx = "pixiedust"
  g.neovide_cursor_vfx_mode = ""
  g.neovide_cursor_vfx_opacity = 120.0
  g.neovide_cursor_vfx_particle_lifetime = 0.5
  g.neovide_cursor_vfx_particle_density = 0.6

  -- The 0.12 progress bar animates on every save; auto-save makes that noisy.
  g.neovide_progress_bar_enabled = false

  M.load_tutor_key()
end

-- Neovide starts Neovim from a login shell, which skips ~/.zshrc. Read the
-- Tutor's OpenAI key from the same Keychain item ~/.zshrc uses (async, and
-- only if it isn't already set).
function M.load_tutor_key()
  if vim.env.OPENAI_API_KEY and vim.env.OPENAI_API_KEY ~= "" then
    return
  end
  local cmd =
    { "/usr/bin/security", "find-generic-password", "-a", vim.env.USER or "", "-s", "nvim-openai-tutor", "-w" }
  pcall(vim.system, cmd, { text = true }, function(result)
    local key = result.code == 0 and vim.trim(result.stdout or "") or ""
    if key ~= "" then
      vim.schedule(function()
        vim.env.OPENAI_API_KEY = key
      end)
    end
  end)
end

function M.toggle_vfx()
  if not vim.g.neovide then
    return
  end
  local on = vim.g.neovide_cursor_vfx_mode ~= ""
  vim.g.neovide_cursor_vfx_mode = on and "" or (M.vfx or "railgun")
  vim.notify("Cursor particles " .. (on and "off" or "on"), vim.log.levels.INFO, { title = "Dojo" })
end

return M
