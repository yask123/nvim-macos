-- Right-click: a short menu that fits what you clicked. In the code: go to
-- definition, references, rename, then cut / copy / paste. In the file tree:
-- new file, new folder, rename, delete, reveal in Finder, copy path.

local M = {}

local function tree()
  return Snacks.picker.get({ source = "explorer" })[1]
end

-- The path of the row under the cursor in the file tree (or the open file).
local function path_here()
  local picker = vim.bo.filetype:match("^snacks_picker") and tree() or nil
  if picker then
    local item = picker:current()
    return item and item.file or nil
  end
  local name = vim.api.nvim_buf_get_name(0)
  return name ~= "" and name or nil
end

function M.tree(action)
  local picker = tree()
  if picker then
    picker:action(action)
  end
end

function M.new_folder()
  local picker = tree()
  if not picker then
    return
  end
  -- The tree's own "add" makes a folder when the name ends in a slash.
  local item = picker:current()
  local dir = item and (item.dir and item.file or vim.fs.dirname(item.file)) or vim.fn.getcwd()
  vim.ui.input({ prompt = "New folder in " .. vim.fn.fnamemodify(dir, ":~:.") .. ": " }, function(name)
    if name and vim.trim(name) ~= "" then
      vim.fn.mkdir(dir .. "/" .. vim.trim(name), "p")
      picker:action("explorer_update")
    end
  end)
end

function M.reveal()
  local path = path_here() or vim.fn.getcwd()
  vim.system({ "open", "-R", path })
end

function M.copy_path()
  local path = path_here()
  if path then
    vim.fn.setreg("+", path)
    vim.notify("Copied " .. vim.fn.fnamemodify(path, ":~"), vim.log.levels.INFO, { title = require("dojo").name })
  end
end

function M.copy_relative_path()
  local path = path_here()
  if path then
    local relative = vim.fn.fnamemodify(path, ":.")
    vim.fn.setreg("+", relative)
    vim.notify("Copied " .. relative, vim.log.levels.INFO, { title = require("dojo").name })
  end
end

local function item(label, rhs, modes)
  label = label:gsub(" ", "\\ "):gsub("%.", "\\.")
  for _, mode in ipairs(modes or { "a" }) do
    vim.cmd(mode .. "noremenu PopUp." .. label .. " " .. rhs)
  end
end

local function rule(index)
  vim.cmd("anoremenu PopUp.-" .. index .. "- <Nop>")
end

local function call(expr)
  return "<Cmd>lua " .. expr .. "<CR>"
end

local function build()
  pcall(vim.cmd, "aunmenu PopUp")
  local ft, bt = vim.bo.filetype, vim.bo.buftype
  if ft:match("^snacks_picker") and tree() then
    item("New File…", call("require('dojo.menu').tree('explorer_add')"))
    item("New Folder…", call("require('dojo.menu').new_folder()"))
    rule(1)
    item("Rename…", call("require('dojo.menu').tree('explorer_rename')"))
    item("Delete", call("require('dojo.menu').tree('explorer_del')"))
    rule(2)
    item("Reveal in Finder", call("require('dojo.menu').reveal()"))
    item("Copy Path", call("require('dojo.menu').copy_path()"))
    item("Copy Relative Path", call("require('dojo.menu').copy_relative_path()"))
    return
  end
  if bt == "terminal" then
    item("Copy", '"+y', { "v" })
    item("Paste", call("require('dojo.actions').paste_terminal()"))
    rule(1)
    item("Hide Terminal", call("require('dojo.actions').toggle_terminal()"))
    return
  end
  if bt == "" and #vim.lsp.get_clients({ bufnr = 0 }) > 0 then
    item("Go to Definition", call("require('dojo.actions').definition()"))
    item("Find All References", call("require('dojo.actions').references()"))
    item("Rename Symbol…", call("require('dojo.actions').rename()"))
    item("Quick Fix…", call("require('dojo.actions').code_action()"))
    item("Show Documentation", call("require('dojo.actions').hover()"))
    rule(1)
  end
  item("Cut", '"+x', { "v" })
  item("Copy", '"+y', { "v" })
  item("Paste", '"+gP', { "n" })
  item("Paste", '"_c<C-r><C-o>+<Esc>', { "v" })
  item("Paste", "<C-r><C-o>+", { "i" })
  item("Select All", call("require('dojo.actions').select_all()"))
  if bt == "" and vim.api.nvim_buf_get_name(0) ~= "" then
    rule(2)
    item("Reveal in Finder", call("require('dojo.menu').reveal()"))
    item("Copy Path", call("require('dojo.menu').copy_path()"))
  end
  rule(3)
  item("Command Palette…", call("require('dojo.actions').palette()"))
end

function M.setup()
  vim.opt.mousemodel = "popup_setpos"
  vim.api.nvim_create_autocmd("MenuPopup", {
    group = vim.api.nvim_create_augroup("DojoMenu", { clear = true }),
    callback = function()
      pcall(build)
    end,
  })
  pcall(build)
end

return M
