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
  -- Phosphor is dark-only: keep the window chrome dark with it.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("DojoChrome", { clear = true }),
    callback = function()
      g.neovide_theme = vim.g.colors_name == "phosphor" and "dark" or "auto"
    end,
  })
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
  -- A slow, smooth "breathing" blink: the cursor fades rather than flashes.
  g.neovide_cursor_smooth_blink = true
  vim.opt.guicursor = {
    "n-v-c-sm:block-Cursor",
    "i-ci-ve:ver25-Cursor",
    "r-cr-o:hor20-Cursor",
    "a:blinkwait900-blinkon700-blinkoff500",
  }
  g.neovide_cursor_antialiasing = true

  g.neovide_cursor_vfx_mode = "" -- no particles

  -- The 0.12 progress bar animates on every save; auto-save makes that noisy.
  g.neovide_progress_bar_enabled = false
end

return M
