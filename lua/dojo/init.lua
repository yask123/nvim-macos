-- Dojo: a calm, learnable, VS Code-flavoured layer over LazyVim.
-- Keys live in lua/dojo/keys.lua; this file wires them up.

local M = {}

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
    elseif entry.run then
      -- Cmd and F-key chords work in every mode: an unmapped <D-…> would be
      -- typed into the file (insert) or sent to the program (terminal).
      local modes = entry.mode or { "n" }
      modes = type(modes) == "string" and { modes } or vim.deepcopy(modes)
      if lhs:match("^<[DF]") or lhs:match("^<S%-F") then
        for _, mode in ipairs({ "n", "i", "x", "t" }) do
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
  require("dojo.cheatsheet").highlights()
  require("dojo.project").title()
  require("dojo.learn").setup()
  require("dojo.writing").setup()
  require("dojo.folds").setup()
  require("dojo.polish").setup()
  require("dojo.sfx").setup()

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
    if vim.fn.argc() == 0 and cwd ~= vim.env.HOME and cwd ~= "/" then
      require("dojo.project").later(function()
        require("dojo.project").open(cwd)
      end)
    end
  end

  local command = vim.api.nvim_create_user_command
  command("Dojo", function()
    require("dojo.cheatsheet").open()
  end, { desc = "Dojo keyboard shortcuts" })
  command("DojoPalette", function()
    require("dojo.palette").open()
  end, { desc = "Dojo command palette" })
  command("DojoOpen", function(opts)
    if opts.args == "" then
      require("dojo.project").choose_folder()
    else
      require("dojo.project").open(opts.args)
    end
  end, { desc = "Open a folder as the project", nargs = "?", complete = "dir" })
end

return M
