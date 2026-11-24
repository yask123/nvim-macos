-- Dojo: a calm, VS Code-flavoured layer over LazyVim.
-- Keys live in lua/dojo/keys.lua; this file wires them up.

local M = {}

-- What the app is called on the Mac (scripts/make-app.sh builds Code.app) and
-- in everything you read: the window title, the welcome screen, messages.
-- The code keeps its first name, Dojo.
M.name = "Code"

local function each_entry(fn)
  for _, group in ipairs(require("dojo.keys")) do
    for _, section in ipairs(group.sections) do
      for _, entry in ipairs(section.items) do
        fn(entry, group)
      end
    end
  end
end

-- From insert or terminal mode, leave it first and run the action once the
-- mode change has happened (pickers and prompts then start in the right mode).
local function from_any_mode(run)
  return function()
    if vim.api.nvim_get_mode().mode:match("^[iRt]") then
      vim.cmd.stopinsert()
      vim.schedule(run)
    else
      run()
    end
  end
end

local function map_entry(entry)
  if not entry.keys then
    return
  end
  local opts = { desc = entry.desc, silent = true, remap = entry.remap }
  for _, lhs in ipairs(entry.keys) do
    if entry.map then
      for mode, rhs in pairs(entry.map) do
        vim.keymap.set(mode, lhs, rhs, opts)
      end
      -- A Mac-style selection (Select mode, lua/dojo/mac.lua) takes the same
      -- chords as a Vim one: flip to Visual, run it, and flip back if the
      -- selection is still there afterwards.
      local visual = entry.map.x
      if type(visual) == "string" and entry.map.s == nil then
        vim.keymap.set("s", lhs, "<C-g>" .. visual .. (visual:match("gv$") and "<C-g>" or ""), opts)
      end
    elseif entry.run then
      -- Cmd and F-key chords work in every mode: an unmapped <D-…> would be
      -- typed into the file (insert) or sent to the program (terminal).
      local modes = entry.mode or { "n" }
      modes = type(modes) == "string" and { modes } or vim.deepcopy(modes)
      if lhs:match("^<[DF]") or lhs:match("^<S%-F") then
        for _, mode in ipairs({ "n", "i", "x", "s", "t" }) do
          if not vim.tbl_contains(modes, mode) then
            table.insert(modes, mode)
          end
        end
      end
      vim.keymap.set(modes, lhs, from_any_mode(entry.run), opts)
    end
  end
end

function M.map_keys()
  each_entry(map_entry)
  for index = 1, 9 do
    vim.keymap.set({ "n", "i" }, "<D-" .. index .. ">", function()
      require("dojo.actions").goto_buffer(index)
    end, { desc = "Go to open file " .. index, silent = true })
  end
  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add({
      { "<D-k>", group = "⌘K chords", mode = { "n", "i" } },
      { "<leader>u", group = "ui" },
    })
  end
end

-- The `dojo` launcher talks to the running app through this socket, so
-- "open this folder" switches the existing window like VS Code does.
M.socket = vim.fn.stdpath("state") .. "/dojo.sock"

function M.serve()
  local ok, chan = pcall(vim.fn.sockconnect, "pipe", M.socket, { rpc = true })
  if ok and chan > 0 then
    vim.fn.chanclose(chan) -- another Dojo window already serves it
    return
  end
  pcall(vim.uv.fs_unlink, M.socket) -- stale socket left by a crash
  pcall(vim.fn.serverstart, M.socket)
end

function M.setup()
  if M._setup then
    return
  end
  M._setup = true

  M.map_keys()
  require("dojo.mac").setup() -- Shift+arrows, the mouse and ⌘A select the Mac way
  require("dojo.mac").swallow_unbound() -- a ⌘ chord nothing is bound to does nothing
  require("dojo.exit").setup() -- quitting never asks, untitled pages come back
  require("dojo.disk").setup() -- files changed on disk show up straight away
  require("dojo.menu").setup() -- right-click
  require("dojo.lang").setup() -- a language's code help installs when you first open it
  require("dojo.cheatsheet").highlights()
  require("dojo.project").title()
  require("dojo.writing").setup()
  require("dojo.folds").setup()
  require("dojo.polish").setup()
  require("dojo.sfx").setup()
  require("dojo.dim").setup()
  require("dojo.signature").setup()
  require("dojo.hold").setup()

  local group = vim.api.nvim_create_augroup("Dojo", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      require("dojo.cheatsheet").highlights()
    end,
  })
  -- Restoring a session (dashboard "s", Space q s) brings files back but not
  -- the file tree; bring it back too, in the Dojo app.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "PersistenceLoadPost",
    callback = function()
      if vim.g.neovide then
        require("dojo.project").later(function()
          require("dojo.project").show_explorer(nil, false)
          require("dojo.folds").refresh()
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      require("dojo.project").title()
    end,
  })

  if vim.g.neovide then
    M.serve()
    -- Started inside a folder (`dojo ~/code/app`, or --chdir): open it as the
    -- project, restoring its last session. From $HOME you get the dashboard.
    local cwd = vim.fn.getcwd()
    -- A folder dropped on the Dojo icon (or given at startup) arrives as a
    -- directory buffer: open it as the project instead.
    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      callback = function(ev)
        local name = vim.api.nvim_buf_get_name(ev.buf)
        if name == "" or vim.bo[ev.buf].buftype ~= "" or vim.fn.isdirectory(name) == 0 then
          return
        end
        require("dojo.project").later(function()
          pcall(vim.api.nvim_buf_delete, ev.buf, { force = true })
          require("dojo.project").open(name)
        end)
      end,
    })
    -- Started with a folder (dropped on the icon while Dojo was closed).
    local arg = vim.fn.argc() == 1 and vim.fn.fnamemodify(vim.fn.argv(0), ":p"):gsub("/$", "") or nil
    if vim.env.DOJO_REQUEST and vim.env.DOJO_REQUEST ~= "" then
      -- Started by the `code` command with files, lines or a wait (lua/dojo/cli.lua).
      require("dojo.project").later(function()
        if not require("dojo.cli").startup() and cwd ~= vim.env.HOME and cwd ~= "/" then
          require("dojo.project").open(cwd)
        end
      end)
    elseif arg and vim.fn.isdirectory(arg) == 1 then
      require("dojo.project").later(function()
        require("dojo.project").open(arg)
      end)
    elseif vim.fn.argc() == 0 and cwd ~= vim.env.HOME and cwd ~= "/" then
      require("dojo.project").later(function()
        require("dojo.project").open(cwd)
      end)
    else
      require("dojo.project").later(function()
        require("dojo.exit").restore() -- untitled pages left open last time
      end)
    end
  end

  local command = vim.api.nvim_create_user_command
  command("Dojo", function()
    require("dojo.cheatsheet").open()
  end, { desc = M.name .. " keyboard shortcuts" })
  command("DojoPalette", function()
    require("dojo.palette").open()
  end, { desc = M.name .. " command palette" })
  command("Review", function(opts)
    if opts.args == "" then
      require("dojo.review").pick()
    else
      require("dojo.review").open(opts.args)
    end
  end, { desc = "Review a pull request (a number or a link)", nargs = "?" })
  command("DojoOpen", function(opts)
    if opts.args == "" then
      require("dojo.project").choose_folder()
    else
      require("dojo.project").open(opts.args)
    end
  end, { desc = "Open a folder as the project", nargs = "?", complete = "dir" })
end

return M
