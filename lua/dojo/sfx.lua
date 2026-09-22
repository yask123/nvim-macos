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

function M.toggle()
  local sfx = engine()
  if sfx and not sfx.blocked then
    sfx.toggle()
  else
    vim.notify("Sound effects are off here (no UI, SSH, or NVIM_SFX=0)", vim.log.levels.INFO, { title = "Dojo" })
  end
end

function M.setup() end

return M
