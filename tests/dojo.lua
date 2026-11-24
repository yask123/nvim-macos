-- Dojo layer: registry integrity, keymaps, cheatsheet, palette, project, sfx.
local function assert_equal(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
  )
end

local function run()
  -- The screen stays at Neovim's own 80 x 24. Changing 'columns' or 'lines'
  -- with no UI attached makes Neovim 0.12 write past the end of a grid it
  -- allocated for 80 columns (seen with Guard Malloc: "header trashed by a
  -- buffer overrun", freed in grid_alloc), and the damaged heap then crashes
  -- somewhere unrelated a moment later. That was this test's "now and then
  -- crashes on its own".
  vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
  vim.wait(200)

  -- Headless Neovim 0.12 can crash inside nvim_get_keymap (the crash report
  -- shows keymap_array reading a stale pointer), and which-key calls it every
  -- time a buffer is entered and from a 50 ms timer. It hasn't happened with
  -- a UI attached. which-key's hints aren't what is tested here, so it sits
  -- the whole test out.
  pcall(vim.api.nvim_del_augroup_by_name, "wk")
  pcall(function()
    require("which-key.buf").get = function() end
  end)
  pcall(function()
    require("which-key.triggers").attach = function() end
  end)

  -- That is one face of a wider problem. Some checks below open a window and
  -- then wait while Neovim works in the background (the file tree, the folder
  -- browser, ⌘R). In this scripted, UI-less mode Neovim 0.12 now and then
  -- corrupts its keymap table during such a wait and crashes at the next
  -- lookup. A normal session doesn't: driving the same windows with real key
  -- presses in 40 server sessions gave no crash. Here a crash is run again by
  -- tests/isolated.sh; the CI runner crashes every time, so it skips them.
  local windows = not vim.env.CI

  local groups = require("dojo.keys")
  local actions = require("dojo.actions")

  -- Every entry is well formed, and no chord is bound twice in the same mode.
  local seen = {}
  local entries = 0
  for _, group in ipairs(groups) do
    assert(type(group.name) == "string" and #group.sections > 0, "group needs a name and sections")
    for _, section in ipairs(group.sections) do
      for _, entry in ipairs(section.items) do
        entries = entries + 1
        assert(type(entry.desc) == "string" and entry.desc ~= "", "entry needs a desc")
        assert(entry.hidden or entry.mac or entry.vim, "entry needs a mac or vim label: " .. entry.desc)
        assert(not (entry.run and entry.map), "entry has both run and map: " .. entry.desc)
        if entry.keys then
          assert(entry.run or entry.map, "entry with keys needs run or map: " .. entry.desc)
          local modes = entry.map and vim.tbl_keys(entry.map) or entry.mode or { "n" }
          modes = type(modes) == "string" and { modes } or modes
          for _, lhs in ipairs(entry.keys) do
            for _, mode in ipairs(modes) do
              local key = mode .. ":" .. vim.fn.keytrans(vim.keycode(lhs))
              -- Alias spellings inside one entry (<D-P> / <D-S-p>) are fine.
              assert(
                seen[key] == nil or seen[key] == entry,
                "chord bound twice: "
                  .. key
                  .. " ("
                  .. entry.desc
                  .. " / "
                  .. (seen[key] and seen[key].desc or "")
                  .. ")"
              )
              seen[key] = entry
            end
          end
        end
        if entry.run then
          assert(type(entry.run) == "function", "run must be a function: " .. entry.desc)
        end
      end
    end
  end
  assert(entries > 60, "registry looks truncated: " .. entries)

  -- The registry is actually mapped (Neovide and Ghostty both send Cmd as <D-…>).
  for lhs, desc in pairs({
    ["<D-p>"] = "Find file",
    ["<D-P>"] = "Command palette",
    ["<D-F>"] = "Find in project",
    ["<D-b>"] = "Show / hide the file tree",
    ["<D-r>"] = "Save & run this file",
    ["<D-/>"] = "Toggle comment",
    ["<D-k><D-s>"] = "Keyboard shortcuts (this sheet)",
    ["<F12>"] = "Go to definition (⌘-click too)",
    ["<leader>?"] = "Keyboard shortcuts (this sheet)",
  }) do
    assert_equal(vim.fn.maparg(lhs, "n", false, true).desc, desc, "mapping " .. lhs)
  end
  -- Neovim treats Cmd+Shift+letter spellings as one key.
  assert_equal(vim.fn.maparg("<D-S-p>", "n", false, true).desc, "Command palette", "<D-S-p> alias")
  assert_equal(vim.fn.maparg("<D-1>", "n", false, true).desc, "Go to open file 1", "⌘1")
  assert_equal(
    vim.fn.keytrans(vim.keycode(vim.fn.maparg("<D-v>", "i", false, true).rhs)),
    "<C-R><C-O>+",
    "⌘V in insert mode"
  )

  -- Every tab of the cheatsheet renders, and Enter-able rows point at actions.
  local cheatsheet = require("dojo.cheatsheet")
  for tab = 1, #groups do
    local win = cheatsheet.open(tab)
    local lines = vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)
    assert(#lines > 4, "cheatsheet tab " .. tab .. " is empty")
    assert(lines[1]:find(groups[tab].name, 1, true), "tab strip shows " .. groups[tab].name)
    for _, item in pairs(win.dojo_items) do
      assert(type(item.run) == "function", "cheatsheet row without action")
    end
    win:close()
  end

  -- The theme picker recolours while you browse and Esc puts yours back.
  local theme = require("dojo.theme")
  local before = vim.g.colors_name
  theme.pick()
  vim.wait(300)
  local picker = Snacks.picker.get()[1]
  assert(picker, "theme picker opens")
  picker.list:move(4, true)
  vim.wait(500, function()
    return vim.g.colors_name ~= before
  end)
  assert(vim.g.colors_name:find(theme.themes[4].name, 1, true) == 1, "theme previews while browsing")
  picker:close()
  vim.wait(500, function()
    return vim.g.colors_name == before
  end)
  assert_equal(vim.g.colors_name, before, "Esc restores the theme")

  -- The palette lists runnable actions, plus lessons when asked.
  local palette = require("dojo.palette")
  local runnable = palette.items()
  local with_lessons = palette.items({ lessons = true })
  assert(#runnable > 35, "palette has too few actions: " .. #runnable)
  assert(#with_lessons > #runnable, "lessons add entries to the palette")
  for _, item in ipairs(runnable) do
    assert(type(item.entry.run) == "function", "palette item without action: " .. item.entry.desc)
  end

  -- Opening a folder switches the working directory.
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  require("dojo.project").open(dir)
  assert_equal(vim.fn.getcwd(), vim.fn.resolve(dir), "project cwd")
  assert(vim.o.titlestring:find(vim.fs.basename(dir), 1, true), "window title names the project")
  assert_equal(vim.o.titlestring, vim.fs.basename(dir) .. " — Code", "window title ends with the app's name")

  -- Opening a project shows its file tree a moment later; let it, then close
  -- it, so it doesn't take the focus from what is tested next.
  local function settle()
    vim.wait(2000, function()
      return #Snacks.picker.get({ source = "explorer" }) > 0
    end)
    for _, picker in ipairs(Snacks.picker.get()) do
      picker:close()
    end
    vim.cmd("silent! only")
  end
  if windows then
    settle()
  end

  -- Recent projects: Code's own list, newest first. Any folder counts, not
  -- only git repositories.
  local recent = require("dojo.recent")
  recent.scratch = {} -- this test's folders live in the temp dir
  recent.file = vim.fn.tempname() .. ".json"
  local root = vim.fn.tempname()
  for _, name in ipairs({ "alpha/inner", "beta", "learn-app", "learn-python", "PyProjects", ".hidden" }) do
    vim.fn.mkdir(root .. "/" .. name, "p")
  end
  vim.fn.writefile({ "print('hi')" }, root .. "/learn-python/two_sum.py")
  root = vim.uv.fs_realpath(root)
  assert_equal(recent.list(), {}, "no projects yet")
  recent.touch(root .. "/alpha")
  recent.touch(root .. "/beta")
  recent.touch(vim.env.HOME)
  local function names()
    return vim.tbl_map(function(entry)
      return entry.name
    end, recent.list())
  end
  assert_equal(names(), { "beta", "alpha" }, "newest project first; the home folder is not a project")
  recent.touch(root .. "/alpha")
  assert_equal(names(), { "alpha", "beta" }, "opening a project again moves it to the top")
  local _, lives = recent.label(root .. "/alpha", 500)
  assert_equal(lives, vim.fn.fnamemodify(root, ":~"), "a project says where it lives")
  vim.fn.delete(root .. "/beta", "d")
  assert_equal(names(), { "alpha" }, "a deleted folder drops off the list")
  vim.fn.mkdir(root .. "/beta", "p")
  local _, where = recent.label("/a/bbbbbbbbbb/cccccccccc/dddddddddd/eeeeeeeeee/name", 20)
  assert_equal(where, "/…/eeeeeeeeee", "a long path is shortened in the middle")
  -- The first launch fills the list from saved sessions (one per folder, plus
  -- %%branch for git branches).
  local sessions = vim.fn.tempname()
  vim.fn.mkdir(sessions, "p")
  local function session(path, suffix)
    vim.fn.writefile({ "" }, sessions .. "/" .. path:gsub("/", "%%") .. (suffix or "") .. ".vim")
  end
  session(root .. "/alpha")
  session(root .. "/beta", "%%feature")
  session(root .. "/beta")
  session(root .. "/gone")
  local seeded = vim.tbl_map(function(entry)
    return entry.path
  end, recent.seed(sessions))
  table.sort(seeded)
  assert_equal(seeded, { root .. "/alpha", root .. "/beta" }, "sessions become recent projects, once each")

  -- The welcome screen lists them with 1-9 to open.
  local welcome = LazyVim.opts("snacks.nvim").dashboard
  local project_rows = welcome.sections[2][1]()
  assert_equal(project_rows[1].key, "1", "first recent project opens with 1")
  assert_equal(project_rows[1].desc[1][1]:gsub("%s+$", ""), "alpha", "welcome screen names the project")

  -- ⌘O: browse for a folder inside the window.
  if windows then
    local browse = require("dojo.browse")
    local function press(lhs, mode)
      local map = vim.fn.maparg(lhs, mode or "n", false, true)
      assert(map.callback, "the browser maps " .. lhs)
      map.callback()
    end
    recent.touch(root .. "/learn-python")
    browse.open({ dir = root, select = "beta" })
    local view = browse.peek()
    assert_equal(
      view.shown,
      { "alpha", "beta", "learn-app", "learn-python", "PyProjects" },
      "folders by name, dot-folders hidden"
    )
    assert_equal(view.selected, "beta", "the browser starts on the folder asked for")
    assert(vim.api.nvim_buf_get_lines(view.buf, 1, 2, false)[1]:find(vim.fs.basename(root), 1, true), "path line")
    press("k")
    press("l")
    assert_equal(browse.peek().dir, root .. "/alpha", "l steps into the lit folder")
    assert_equal(browse.peek().shown, { "inner" }, "and lists what is inside")
    press("h")
    assert_equal({ browse.peek().dir, browse.peek().selected }, { root, "alpha" }, "h steps back out, same row lit")
    vim.wait(1000, function()
      return #browse.peek().inside > 0
    end)
    assert_equal(browse.peek().inside, { "inner/" }, "the right column shows what is inside")
    press(".")
    assert_equal(browse.peek().shown[1], ".hidden", ". shows dot-folders")
    press(".")
    browse.type("lea")
    view = browse.peek()
    assert_equal(view.shown, { "learn-python", "learn-app" }, "typing narrows; folders you've opened come first")
    assert_equal(view.target, root .. "/learn-python", "Enter would open the first match")
    browse.type("py")
    assert_equal(browse.peek().selected, "learn-python", "a folder you've opened beats a closer match you haven't")
    browse.type("zzz")
    assert_equal(browse.peek().target, nil, "nothing matches, nothing to open")
    browse.type("learn-p")
    press("<CR>", "i")
    assert(not browse.is_open(), "Enter closes the browser")
    vim.wait(2000, function()
      return vim.fn.getcwd() == root .. "/learn-python"
    end)
    assert_equal(vim.fn.getcwd(), root .. "/learn-python", "Enter opens the folder as the project")
    assert_equal(names()[1], "learn-python", "and it tops the recent list")
    settle()
    browse.open()
    assert_equal(
      { browse.peek().dir, browse.peek().selected },
      { root, "learn-python" },
      "the browser starts beside the project you are in"
    )
    browse.open()
    assert(not browse.is_open(), "⌘O again closes the browser")
  end

  -- ⌘, : the Settings sheet lists a few choices, and remembers them.
  local settings = require("dojo.settings")
  settings.file = vim.fn.tempname() .. ".json"
  assert_equal(settings.get("zoom", 1), 1, "a setting has a default")
  settings.set("zoom", 1.1)
  assert_equal(vim.json.decode(table.concat(vim.fn.readfile(settings.file))).zoom, 1.1, "settings are written down")
  if windows then
    settings.open()
    local setting_rows = settings.peek()
    assert_equal(setting_rows[1].name, "Colour theme", "settings start with the theme")
    assert(setting_rows[1].value ~= "", "and say which theme is on")
    assert_equal(setting_rows[#setting_rows].name, "Config files", "config files are the last row")
    settings.open()
    assert(not settings.is_open(), "⌘, again closes the sheet")
  end

  -- ⌘R runs the file in a bottom panel; focus returns to the code when it
  -- ends, the output stays, and ⌘J closes it. A shell script, so no language
  -- server attaches and scans the keymaps (see the note at the top).
  if not windows then
    goto after_run
  end
  do
    settle()
    local script = vim.fn.tempname() .. ".sh"
    vim.fn.writefile({ 'echo "hello from run"' }, script)
    vim.cmd.edit(script)
    local code_win = vim.api.nvim_get_current_win()
    local runner = require("config.runner")
    runner.run()
    assert(runner.is_open(), "run opens the output panel")
    vim.wait(5000, function()
      return vim.api.nvim_get_current_win() == code_win
    end)
    assert_equal(vim.api.nvim_get_current_win(), code_win, "focus returns to the code when the run ends")
    local output = ""
    vim.wait(2000, function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == "terminal" then
          output = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
        end
      end
      return output:find("hello from run", 1, true) ~= nil
    end)
    assert(output:find("hello from run", 1, true), "run output is shown: " .. output)
    actions.toggle_terminal()
    assert(not runner.is_open(), "⌘J closes the run output")
  end
  ::after_run::

  -- Sound is inert without a UI and never errors.
  assert(package.loaded.sfx == nil or not require("sfx").active(), "sfx must stay silent headless")
  require("dojo.sfx").play("open")
  require("dojo.sfx").run_result(0)

  -- Every curated theme loads.
  for _, t in ipairs(theme.themes) do
    local ok, err = pcall(vim.cmd.colorscheme, t.name)
    assert(ok, "theme does not load: " .. t.name .. " " .. tostring(err))
  end

  -- Commands exist.
  for _, name in ipairs({ "Dojo", "DojoPalette", "DojoOpen" }) do
    assert_equal(vim.fn.exists(":" .. name), 2, "command " .. name)
  end

  -- The call hint: names and defaults, the argument you are on lit up, and
  -- the fullest form when the server leads with an empty one (defaultdict).
  local signature = require("dojo.signature")
  local function form(label, ...)
    local parameters, from = {}, 1
    for _, text in ipairs({ ... }) do
      local s, e = label:find(text, from, true)
      assert(s, "bad test parameter: " .. text)
      table.insert(parameters, { label = { s - 1, e } })
      from = e + 1
    end
    return { label = label, parameters = parameters }
  end
  local function lit(row)
    for _, chunk in ipairs(row) do
      if chunk[2] == "DojoSignatureActive" then
        return chunk[1]
      end
    end
  end
  local factory = "default_factory: (() -> _VT@defaultdict) | None"
  local defaultdict = {
    activeSignature = 0,
    signatures = {
      form("() -> defaultdict"),
      form("(**kwargs: _VT@defaultdict) -> defaultdict", "**kwargs: _VT@defaultdict"),
      form("(" .. factory .. ", /) -> defaultdict", factory, "/"),
      form(
        "("
          .. factory
          .. ", map: SupportsKeysAndGetItem[str, _VT@defaultdict], /, **kwargs: _VT@defaultdict) -> defaultdict",
        factory,
        "map: SupportsKeysAndGetItem[str, _VT@defaultdict]",
        "/",
        "**kwargs: _VT@defaultdict"
      ),
    },
  }
  local rows = signature.render(defaultdict)
  assert_equal(signature.text(rows), { "(default_factory, map, /, **kwargs)  +3" }, "defaultdict( hint")
  assert_equal(lit(rows[1]), "default_factory", "defaultdict( lights the first argument")
  assert_equal(
    signature.text(signature.render(defaultdict, { all = true })),
    { "()", "(**kwargs)", "(default_factory, /)", "(default_factory, map, /, **kwargs)" },
    "every way to call defaultdict"
  )
  -- While you type, the hint stays on the form it showed: the server moves to
  -- (default_factory, /) after the first character, but only the lit name moves.
  local _, shape = signature.render(defaultdict)
  defaultdict.activeSignature, defaultdict.activeParameter = 2, 0
  assert_equal(signature.text((signature.render(defaultdict))), { "(default_factory, /)  +3" }, "the server's pick")
  rows = signature.render(defaultdict, { keep = shape })
  assert_equal(signature.text(rows), { "(default_factory, map, /, **kwargs)  +3" }, "the hint keeps its form")
  assert_equal(lit(rows[1]), "default_factory", "and lights what the server says you are on")
  local two_sum = {
    activeSignature = 0,
    activeParameter = 1,
    signatures = { form("(nums: list[int], target: int = 0) -> list[int]", "nums: list[int]", "target: int = 0") },
  }
  rows = signature.render(two_sum)
  assert_equal(signature.text(rows), { "(nums, target: int = 0)" }, "a plain type shows for the argument you are on")
  assert_equal(lit(rows[1]), "target", "the second argument is lit after the comma")
  two_sum.activeParameter = 5
  assert_equal(lit(signature.render(two_sum)[1]), nil, "past the last argument nothing is lit")
  assert(
    signature.text(signature.render(two_sum, { width = 12 }))[1]:find("…", 1, true),
    "a narrow window trims the hint"
  )
  assert_equal(signature.render({ signatures = {} }), nil, "no signature, no hint")
  assert_equal(signature.render({ signatures = { form("() -> None") } }), nil, "a call that takes nothing has no hint")

  -- Holding h j k l speeds up; taps and counts stay exact.
  local hold = require("dojo.hold")
  local function presses(key, count, gap, at)
    local total = 0
    for i = 0, count - 1 do
      total = total + hold.steps(key, at + i * gap)
    end
    return total
  end
  hold.reset()
  assert_equal(presses("j", 5, 130, 10000), 5, "five taps of j are five lines")
  assert_equal(presses("j", 2, 85, 20000), 2, "a fast double tap is two lines")
  -- A held key: macOS waits half a second, then repeats about every 83 ms.
  local held = hold.steps("j", 30000) + presses("j", 30, 83, 30500)
  assert(held > 150 and held < 260, "three seconds of holding j covers far more than 31 lines: " .. held)
  assert_equal(hold.steps("k", 33000), 1, "another key starts from one step again")
  assert_equal(vim.fn.maparg("j", "n", false, true).desc, "Down (hold to go faster)", "j mapping")
  assert_equal(vim.fn.maparg("l", "x", false, true).desc, "Right (hold to go faster)", "l mapping in visual mode")

  -- Actions table has no dangling references from the registry.
  for _, group in ipairs(groups) do
    for _, section in ipairs(group.sections) do
      for _, entry in ipairs(section.items) do
        if entry.run then
          local found = false
          for _, fn in pairs(actions) do
            found = found or fn == entry.run
          end
          assert(found, "registry action not in dojo.actions: " .. entry.desc)
        end
      end
    end
  end

  io.stdout:write(("Dojo test passed (%d registry entries, %d palette actions)\n"):format(entries, #runnable))
end

-- noice (loaded on VeryLazy) captures error messages; report on stderr instead.
local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write("Dojo test failed: " .. tostring(err) .. "\n")
  os.exit(1)
end
-- Exit straight away: which-key polls every 50 ms and schedules keymap scans
-- after buffer churn; Neovim can crash running one during exit teardown.
io.stdout:flush()
os.exit(0)
