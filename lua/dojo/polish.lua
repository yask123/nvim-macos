-- Highlights that are always visible, whatever the colour theme. Some themes
-- make the selection or "other uses of this word" almost the background
-- colour; after every theme load, derive them from the theme's own accent.

local M = {}

local function get(group, attr)
  return vim.api.nvim_get_hl(0, { name = group, link = false })[attr]
end

local function blend(fg, bg, alpha)
  local function channel(c, shift)
    return bit.band(bit.rshift(c, shift), 0xff)
  end
  local out = 0
  for _, shift in ipairs({ 16, 8, 0 }) do
    local v = math.floor(channel(fg, shift) * alpha + channel(bg, shift) * (1 - alpha) + 0.5)
    out = out + bit.lshift(v, shift)
  end
  return out
end

function M.apply()
  local bg = get("Normal", "bg")
  local fg = get("Normal", "fg")
  if not bg or not fg then
    return -- transparent theme: leave it alone
  end
  local accent = get("Function", "fg") or get("Special", "fg") or fg
  local warm = get("DiagnosticWarn", "fg") or get("String", "fg") or fg

  local hl = vim.api.nvim_set_hl
  -- Selection: clearly tinted with the theme accent, text keeps its colours.
  hl(0, "Visual", { bg = blend(accent, bg, 0.30) })
  hl(0, "VisualNOS", { bg = blend(accent, bg, 0.22) })
  -- Other uses of the word under the cursor: a soft tint plus an underline.
  local ref = { bg = blend(fg, bg, 0.12), underline = false }
  hl(0, "LspReferenceText", ref)
  hl(0, "LspReferenceRead", ref)
  hl(0, "LspReferenceWrite", { bg = blend(accent, bg, 0.18) })
  -- Search: all matches warm and readable, the current match stronger.
  hl(0, "Search", { bg = blend(warm, bg, 0.30), fg = fg })
  hl(0, "IncSearch", { bg = blend(warm, bg, 0.60), fg = bg, bold = true })
  hl(0, "CurSearch", { bg = blend(warm, bg, 0.60), fg = bg, bold = true })
  hl(0, "MatchParen", { bg = blend(accent, bg, 0.25), bold = true })
end

function M.setup()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("DojoPolish", { clear = true }),
    callback = function()
      vim.schedule(M.apply) -- after plugins that also react to ColorScheme
    end,
  })
  M.apply()
end

return M
