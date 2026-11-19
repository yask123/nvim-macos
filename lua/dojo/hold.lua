-- Hold h, j, k or l and the cursor picks up speed.
--
-- A held key repeats only as fast as macOS sends it (about 12 times a second
-- out of the box), so crossing a file takes an age. Once a key is clearly
-- being held, each repeat is worth more than one step, and the extra steps
-- are spread over the gap until the next repeat, so the cursor glides instead
-- of jumping. Taps are untouched: jjj is always three lines, and so is 3j.

local M = {}

local api = vim.api
local ns = api.nvim_create_namespace("dojo.hold")

-- Steps a second: where a hold starts, where it tops out, and the seconds it
-- takes to get there. Lines for j and k, columns for h and l.
local SPEED = {
  j = { from = 32, to = 110, ramp = 1.6 },
  k = { from = 32, to = 110, ramp = 1.6 },
  h = { from = 45, to = 150, ramp = 1.2 },
  l = { from = 45, to = 150, ramp = 1.2 },
}
local REPEAT = 105 -- ms. Two gaps this short in a row are a held key: nobody taps ten times a second.
local RELEASE = 170 -- ms. During a hold, a longer gap than this means the key was let go.

local press = {
  key = nil,
  at = 0, -- when it last arrived (ms)
  streak = 0, -- repeats in a row
  since = 0, -- when the hold was recognised
  carry = 0, -- fraction of a step owed
  gap = 83, -- the Mac's repeat interval, measured as it goes
}

-- How many steps this press of `key` at `now` (ms) is worth.
function M.steps(key, now)
  local gap = now - press.at
  local same = key == press.key
  press.at = now
  if not same or gap > (press.streak >= 2 and RELEASE or REPEAT) then
    press.key, press.streak, press.carry = key, 0, 0
    return 1
  end
  press.streak = press.streak + 1
  if press.streak < 2 then
    return 1
  elseif press.streak == 2 then
    press.since = now
  end
  press.gap = press.gap + (gap - press.gap) * 0.3
  local speed = SPEED[key]
  local held = (now - press.since) / 1000
  local rate = speed.from + (speed.to - speed.from) * math.min(held / speed.ramp, 1)
  local owed = rate * gap / 1000 + press.carry
  local steps = math.max(1, math.floor(owed))
  press.carry = math.max(0, owed - steps)
  return steps
end

function M.reset()
  press.key, press.at, press.streak, press.carry, press.gap = nil, 0, 0, 0, 83
end

-- The steps after the first, one at a time until the next repeat arrives.
local glide = { timer = nil, left = 0, motion = nil, moving = false }

local function stop()
  glide.left = 0
  if glide.timer then
    glide.timer:stop()
  end
end

local function tick()
  if glide.left <= 0 then
    return stop()
  end
  local mode = api.nvim_get_mode()
  if mode.blocking or not (mode.mode == "n" or mode.mode:find("^[vV\22]")) then
    return stop()
  end
  local before = api.nvim_win_get_cursor(0)
  glide.left = glide.left - 1
  glide.moving = true
  pcall(vim.cmd, "normal! " .. glide.motion)
  glide.moving = false
  local after = api.nvim_win_get_cursor(0)
  if glide.left == 0 or (after[1] == before[1] and after[2] == before[2]) then
    stop() -- done, or at the edge of the file or line
  end
end

local function start(motion, count)
  glide.timer = glide.timer or assert(vim.uv.new_timer())
  glide.motion, glide.left = motion, count
  local every = math.max(4, math.floor(press.gap / (count + 1)))
  glide.timer:start(every, every, vim.schedule_wrap(tick))
end

local function multiple_cursors()
  local mc = package.loaded["multicursor-nvim"]
  return mc and mc.hasCursors and mc.hasCursors()
end

local function mapping(key)
  -- j and k move by screen line, as LazyVim has them (soft-wrapped lines).
  local motion = (key == "j" or key == "k") and "g" .. key or key
  return function()
    -- A count (5j), a replayed macro and multiple cursors are exact.
    if vim.v.count > 0 or vim.fn.reg_executing() ~= "" or multiple_cursors() then
      stop()
      return key
    end
    local steps = M.steps(key, vim.uv.hrtime() / 1e6)
    -- Steps the last repeat still owed are taken now, so no distance is lost.
    local owed = glide.motion == motion and glide.left or 0
    stop()
    if steps > 1 then
      start(motion, steps - 1)
    end
    return owed > 0 and (owed + 1) .. motion or motion
  end
end

function M.setup()
  local names = { h = "Left", j = "Down", k = "Up", l = "Right" }
  for key, name in pairs(names) do
    vim.keymap.set(
      { "n", "x" },
      key,
      mapping(key),
      { expr = true, silent = true, desc = name .. " (hold to go faster)" }
    )
  end
  -- Any other key ends the glide where the cursor is: what you see is where
  -- the next command acts.
  vim.on_key(function(_, typed)
    if glide.left > 0 and not glide.moving and typed ~= "" and typed ~= press.key then
      stop()
    end
  end, ns)
end

return M
