-- Dim the desktop behind the Dojo window (⌘K D). A tiny native helper
-- (extras/dojo/dim.swift) draws a click-through veil under the window while
-- Dojo is the active app; it fades away when you switch to anything else.
-- Dojo app only. Built on first use with swiftc (~1 s, in the background).

local M = {}

M.opacity = 0.45
M.source = vim.fn.stdpath("config") .. "/extras/dojo/dim.swift"
M.bin = vim.fn.stdpath("data") .. "/dojo/dojo-dim"
M.state = vim.fn.stdpath("state") .. "/dojo-dim"

local job

local function saved_on()
  local ok, lines = pcall(vim.fn.readfile, M.state)
  return not (ok and lines[1] == "off")
end

local function save(on)
  vim.fn.mkdir(vim.fs.dirname(M.state), "p")
  vim.fn.writefile({ on and "on" or "off" }, M.state)
end

local function stale()
  local bin, src = vim.uv.fs_stat(M.bin), vim.uv.fs_stat(M.source)
  return not bin or (src and src.mtime.sec > bin.mtime.sec)
end

local function build(done)
  if not stale() then
    return done()
  end
  if vim.fn.executable("swiftc") == 0 then
    return -- no Xcode command line tools: quietly skip the effect
  end
  vim.fn.mkdir(vim.fs.dirname(M.bin), "p")
  vim.system({ "swiftc", "-O", "-swift-version", "5", M.source, "-o", M.bin }, { text = true }, function(result)
    if result.code == 0 then
      vim.schedule(done)
    end
  end)
end

local function start()
  if job or vim.v.exiting ~= vim.NIL then
    return
  end
  local lock = vim.fn.stdpath("state") .. "/dojo-dim.lock"
  local id = vim.fn.jobstart({ M.bin, tostring(M.opacity), lock }, {
    on_exit = function()
      job = nil
    end,
  })
  if id > 0 then
    job = id
  end
end

function M.enabled()
  return saved_on()
end

function M.set(on)
  save(on)
  if job then
    vim.fn.chansend(job, on and "on\n" or "off\n")
  elseif on then
    build(start)
  end
end

function M.toggle()
  local on = not saved_on()
  M.set(on)
  vim.notify("Desktop dimming " .. (on and "on" or "off"), vim.log.levels.INFO, { title = "Dojo" })
end

function M.setup()
  if not vim.g.neovide or vim.fn.has("mac") == 0 or not saved_on() then
    return
  end
  vim.defer_fn(function()
    build(start)
  end, 100)
end

return M
