-- sfx: tasteful, low-latency game-style sound effects for Neovim / Neovide (macOS).
-- Talks to a persistent `nvsfx` daemon (Swift + AVAudioEngine) over a stdin pipe:
-- one short line per event, no process spawn per sound, nothing blocking on the UI thread.
--
--   require("sfx").setup({ volume = 0.35 })
--   :Sfx toggle | on | off | volume 0.2 | test | build | status
--
local M = {}

local uv = vim.uv or vim.loop
local src_dir = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))

---@class SfxOptions
local defaults = {
  enabled = true,
  volume = 0.35, -- daemon master volume (0..1); samples are pre-mastered quiet (-20 dBFS ticks)
  bin = vim.fn.stdpath("data") .. "/sfx/nvsfx",
  sounds = vim.fn.stdpath("data") .. "/sfx/sounds",
  source = src_dir, -- where nvsfx.swift + gen_sfx.py live (auto-build if bin is missing/stale)
  buffer_frames = 256, -- CoreAudio IO buffer (~5.8 ms at 44.1 kHz)
  idle_suspend = 20, -- seconds of silence before the daemon pauses the audio engine (0 = never)
  mute_when_unfocused = true, -- FocusLost/FocusGained (Neovide and Ghostty both report focus)
  typing_in_prompts = false, -- ticks in picker/prompt/terminal buffers
  events = { -- set any to false to silence it
    typing = true,
    enter = true,
    backspace = true,
    mode = true,
    visual = false,
    save = true,
    run = true,
    start = true,
    quit = false,
    yank = true,
    paste = true,
    undo = true,
  },
  -- minimum ms between two emits of the same sound (Lua side; the daemon has its own backstop)
  rate_ms = {
    key = 28,
    space = 28,
    backspace = 28,
    enter = 60,
    mode_insert = 90,
    mode_normal = 90,
    mode_visual = 120,
    save = 600,
    start = 4000,
    run_ok = 250,
    run_err = 250,
    yank = 120,
    paste = 120,
    undo = 70,
    redo = 70,
    quit = 1000,
    notify = 400,
  },
  force = false, -- play even without an attached UI (benchmarks only)
}

M.opts = vim.deepcopy(defaults)
local proc ---@type vim.SystemObj?
local focused = true
local last = {} ---@type table<string, integer>
local autosaving = false
local respawns = 0
local ns = vim.api.nvim_create_namespace("sfx")

local function has_ui()
  return M.opts.force or #vim.api.nvim_list_uis() > 0
end

--- Should anything make noise right now?
function M.active()
  return M.opts.enabled and (focused or not M.opts.mute_when_unfocused) and proc ~= nil
end

local function send(line)
  if not proc then
    return
  end
  local ok = pcall(proc.write, proc, line .. "\n")
  if not ok then
    proc = nil
  end
end

--- Emit a sound event by name (key, enter, save, run_ok, run_err, ...). Cheap: ~µs.
function M.emit(name)
  if not M.active() then
    return
  end
  local now = uv.now()
  local gap = M.opts.rate_ms[name] or 60
  if last[name] and now - last[name] < gap then
    return
  end
  last[name] = now
  send("play " .. name) -- `play` prefix: names like `quit` are also daemon commands
end

-- ------------------------------------------------------------------ daemon lifecycle
local function stale(bin, srcfile)
  local b, s = uv.fs_stat(bin), uv.fs_stat(srcfile)
  return not b or (s and s.mtime.sec > b.mtime.sec)
end

--- Build the daemon + synthesize the sample pack (async). ~3 s with swiftc, ~0.2 s for the WAVs.
function M.build(cb)
  local o = M.opts
  vim.fn.mkdir(vim.fs.dirname(o.bin), "p")
  vim.system(
    { "swiftc", "-O", "-swift-version", "5", o.source .. "/nvsfx.swift", "-o", o.bin },
    { text = true },
    function(r)
      if r.code ~= 0 then
        vim.schedule(function()
          if vim.v.exiting ~= vim.NIL then
            return
          end
          vim.notify("sfx: swiftc failed\n" .. (r.stderr or ""), vim.log.levels.ERROR)
        end)
        return
      end
      vim.system({ "python3", o.source .. "/gen_sfx.py", o.sounds }, { text = true }, function(r2)
        vim.schedule(function()
          if vim.v.exiting ~= vim.NIL then
            return
          end
          if r2.code ~= 0 then
            vim.notify("sfx: sample generation failed\n" .. (r2.stderr or ""), vim.log.levels.ERROR)
          elseif cb then
            cb()
          end
        end)
      end)
    end
  )
end

function M.start()
  if proc or not has_ui() or M.blocked then
    return
  end
  local o = M.opts
  if stale(o.bin, o.source .. "/nvsfx.swift") or stale(o.sounds .. "/save.wav", o.source .. "/gen_sfx.py") then
    return M.build(M.start)
  end
  local this ---@type vim.SystemObj?
  local started = uv.now()
  local ok, obj = pcall(vim.system, {
    o.bin,
    "--dir",
    o.sounds,
    "--volume",
    tostring(o.volume),
    "--buffer",
    tostring(o.buffer_frames),
    "--idle-suspend",
    tostring(o.idle_suspend),
  }, {
    stdin = true,
    stdout = false,
    stderr = false,
  }, function(res)
    -- daemon died (device error, crash). Respawn a couple of times, then give up quietly.
    vim.schedule(function()
      if vim.v.exiting ~= vim.NIL then
        return
      end
      if proc ~= this then
        return
      end -- an older daemon (after :Sfx off/on) exiting late
      proc = nil
      if res.signal == 0 and res.code == 0 then
        return
      end
      -- only crashes in quick succession count towards giving up
      respawns = uv.now() - started > 30000 and 1 or respawns + 1
      if respawns <= 3 and M.opts.enabled then
        vim.defer_fn(M.start, 500 * respawns)
      end
    end)
  end)
  if ok then
    proc, this = obj, obj
  end
end

function M.stop()
  if proc then
    pcall(proc.write, proc, nil) -- close stdin -> daemon lets tails ring out, then exits
    proc = nil
  end
end

-- ------------------------------------------------------------------ user controls
function M.set_enabled(v)
  if M.blocked then
    v = false
  end
  M.opts.enabled = v
  if v then
    M.start()
  else
    M.stop()
  end
end

function M.toggle()
  M.set_enabled(not M.opts.enabled)
  vim.notify("Sound effects " .. (M.opts.enabled and "on" or "off"))
end

function M.volume(v)
  M.opts.volume = math.max(0, math.min(1, tonumber(v) or M.opts.volume))
  send("vol " .. M.opts.volume)
end

function M.test()
  local seqs = {
    "start",
    "key",
    "key",
    "key",
    "enter",
    "save",
    "run_ok",
    "run_err",
    "mode_insert",
    "mode_normal",
    "yank",
    "paste",
    "undo",
  }
  for i, s in ipairs(seqs) do
    vim.defer_fn(function()
      last[s] = nil
      M.emit(s)
    end, (i - 1) * 450)
  end
end

--- Call from a runner when a program finishes.
function M.run_result(code)
  if M.opts.events.run then
    M.emit(code == 0 and "run_ok" or "run_err")
  end
end

-- ------------------------------------------------------------------ event wiring
local CR, BS, CR2 = vim.keycode("<CR>"), vim.keycode("<BS>"), vim.keycode("<C-r>")
-- keys that take the NEXT key as an argument (f{char}, r{char}, "{reg}, m{mark}, g/z/[ prefixes...).
-- nvim_get_mode().blocking is always false inside on_key, so we track the previous key ourselves.
local ARG_PREFIX = {
  f = 1,
  F = 1,
  t = 1,
  T = 1,
  r = 1,
  g = 1,
  z = 1,
  m = 1,
  ["'"] = 1,
  ["`"] = 1,
  ['"'] = 1,
  ["@"] = 1,
  q = 1,
  ["["] = 1,
  ["]"] = 1,
  Z = 1,
  [vim.keycode("<C-w>")] = 1,
}
local prev_key = ""
local pending ---@type {name: string, t: integer}?  confirmed by TextChanged (no sound if nothing changed)

local function on_key(key, typed)
  if not M.active() then
    return
  end
  local k = (typed and typed ~= "") and typed or key
  if k == nil or k == "" then
    return
  end
  local mode = vim.api.nvim_get_mode().mode
  local m = mode:sub(1, 1)
  local ev = M.opts.events
  if m == "i" or m == "R" then
    prev_key = ""
    if vim.bo.buftype ~= "" and not M.opts.typing_in_prompts then
      return
    end
    if k == CR then
      if ev.enter then
        M.emit("enter")
      end
    elseif k == BS then
      if ev.backspace then
        M.emit("backspace")
      end
    elseif k == " " then
      if ev.typing then
        M.emit("space")
      end
    elseif ev.typing then
      local b = k:byte(1)
      -- printable ASCII or a UTF-8 lead byte; special keys start with 0x80 (K_SPECIAL)
      if (#k == 1 and b >= 33 and b < 127) or (b >= 0xC2 and b <= 0xF4) then
        M.emit("key")
      end
    end
    return
  end
  local was_arg = ARG_PREFIX[prev_key] ~= nil
  prev_key = was_arg and "" or k -- an argument key is consumed; don't let it prefix the next key
  if was_arg then
    return
  end
  if mode == "n" then
    if ev.undo and k == "u" then
      pending = { name = "undo", t = uv.now() }
    elseif ev.undo and k == CR2 then
      pending = { name = "redo", t = uv.now() }
    elseif ev.paste and (k == "p" or k == "P") then
      pending = { name = "paste", t = uv.now() }
    end
  elseif (m == "v" or m == "V" or m == "\22") and ev.paste and (k == "p" or k == "P") then
    pending = { name = "paste", t = uv.now() }
  end
end

local function confirm_pending()
  if pending and uv.now() - pending.t < 250 then
    M.emit(pending.name)
  end
  pending = nil
end

local function file_buf(buf)
  return vim.bo[buf or 0].buftype == ""
end

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  local o = M.opts

  vim.api.nvim_create_user_command("Sfx", function(a)
    local sub, arg = a.fargs[1] or "toggle", a.fargs[2]
    if sub == "toggle" then
      M.toggle()
    elseif sub == "on" then
      M.set_enabled(true)
    elseif sub == "off" then
      M.set_enabled(false)
    elseif sub == "volume" then
      M.volume(arg)
    elseif sub == "test" then
      M.test()
    elseif sub == "build" then
      M.stop()
      M.build(function()
        vim.notify("sfx: built")
        M.start()
      end)
    elseif sub == "status" then
      vim.notify(
        ("sfx: enabled=%s running=%s focused=%s volume=%.2f ui=%s"):format(
          tostring(o.enabled),
          tostring(proc ~= nil),
          tostring(focused),
          o.volume,
          tostring(has_ui())
        )
      )
    end
  end, {
    nargs = "*",
    complete = function()
      return { "toggle", "on", "off", "volume", "test", "build", "status" }
    end,
  })

  -- Never make noise in headless runs (tests, scripts, `nvim --headless`), over SSH, or when opted out.
  M.blocked = vim.env.NVIM_SFX == "0" or vim.env.SSH_CONNECTION ~= nil
  if M.blocked then
    o.enabled = false
  end

  local g = vim.api.nvim_create_augroup("sfx", { clear = true })
  local au = function(ev, pattern, fn)
    vim.api.nvim_create_autocmd(ev, { group = g, pattern = pattern, callback = fn })
  end

  -- start the daemon once a UI is attached (UIEnter never fires in --headless)
  local function boot()
    if not o.enabled then
      return
    end
    M.start()
    if o.events.start then
      vim.defer_fn(function()
        M.emit("start")
      end, 120)
    end
  end
  au("UIEnter", nil, boot)
  -- lazy-loaded (e.g. event = "VeryLazy") after UIEnter already fired: boot now
  if o.force or (vim.v.vim_did_enter == 1 and has_ui()) then
    boot()
  end

  au("FocusLost", nil, function()
    focused = false
  end)
  au("FocusGained", nil, function()
    focused = true
  end)
  au("VimLeavePre", nil, function()
    if o.events.quit then
      M.emit("quit")
    end
    M.stop()
  end)

  au("ModeChanged", nil, function(a)
    if not o.events.mode or not file_buf(a.buf) then
      return
    end
    local old, new = vim.v.event.old_mode:sub(1, 1), vim.v.event.new_mode:sub(1, 1)
    if new == "i" and old ~= "i" then
      M.emit("mode_insert")
    elseif new == "n" and (old == "i" or old == "v" or old == "V" or old == "\22") then
      M.emit("mode_normal")
    elseif o.events.visual and (new == "v" or new == "V" or new == "\22") and old == "n" then
      M.emit("mode_visual")
    end
  end)

  -- auto-save.nvim writes are silent; only explicit saves get the coin
  au("User", "AutoSaveWritePre", function()
    autosaving = true
  end)
  au("User", "AutoSaveWritePost", function()
    autosaving = false
  end)
  au("BufWritePost", nil, function(a)
    if o.events.save and not autosaving and file_buf(a.buf) then
      M.emit("save")
    end
  end)

  au("TextYankPost", nil, function()
    if o.events.yank and vim.v.event.operator == "y" then
      M.emit("yank")
    end
  end)

  au({ "TextChanged", "TextChangedI" }, nil, confirm_pending)

  au("DirChanged", "global", function()
    if o.events.start then
      M.emit("start")
    end -- switching project = new level
  end)

  -- on_key listeners are removed on error, so never let one escape
  vim.on_key(function(k, t)
    pcall(on_key, k, t)
  end, ns)
end

return M
