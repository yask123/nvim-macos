-- Dojo's hook into the sound engine (sfx/ in this repo). Most sounds fire on
-- their own from editor events; Dojo only adds a few UI cues. Safe when the
-- engine is not loaded (headless, SSH, NVIM_SFX=0).

local M = {}

local cues = {} -- UI cues (e.g. { open = "notify" }); none by default

local function engine()
  local ok, sfx = pcall(require, "sfx")
  return ok and sfx or nil
end

function M.play(name)
  local sfx = engine()
  if sfx and cues[name] then
    sfx.emit(cues[name])
  end
end

function M.run_result(code)
  local sfx = engine()
  if sfx then
    sfx.run_result(code)
  end
end

-- Can sound play here at all? (Not headless, over SSH, or with NVIM_SFX=0.)
function M.available()
  local sfx = engine()
  return sfx ~= nil and sfx.opts ~= nil and not sfx.blocked
end

function M.enabled()
  local sfx = engine()
  return sfx ~= nil and sfx.opts ~= nil and sfx.opts.enabled == true
end

-- Turn typing sounds on or off, and remember it for next launch.
function M.set(on)
  if not M.available() then
    return
  end
  engine().set_enabled(on)
  require("dojo.settings").set("sound", on)
end

function M.toggle()
  if M.available() then
    M.set(not M.enabled())
    vim.notify(
      "Typing sounds " .. (M.enabled() and "on" or "off"),
      vim.log.levels.INFO,
      { title = require("dojo").name }
    )
  else
    vim.notify(
      "Sound effects are off here (no UI, SSH, or NVIM_SFX=0)",
      vim.log.levels.INFO,
      { title = require("dojo").name }
    )
  end
end

function M.setup() end

return M
