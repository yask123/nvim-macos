-- Folds as an outline: see a file from the top level, then open it up one
-- level at a time. Folds come from treesitter (functions, classes, blocks).
--
--   ⌘K ⌘0  overview: fold everything        (zM)
--   ⌘K ⌘]  one level deeper, whole file      (zr)
--   ⌘K ⌘[  one level shallower, whole file   (zm)
--   ⌘K ⌘J  unfold everything                 (zR)
--   ⌥⌘]    open the fold under the cursor    (zo)   ⌥⌘[ close it (zc)
--   ↩ / za toggle the fold under the cursor; zj / zk jump between folds
--
-- Big files (over M.big_file lines) open as an overview automatically.

local M = {}

M.big_file = 300

local function level_info(level)
  local max = 0
  for lnum = 1, vim.fn.line("$") do
    max = math.max(max, vim.fn.foldlevel(lnum))
  end
  vim.notify(
    ("Fold level %d of %d"):format(math.min(level, max), max),
    vim.log.levels.INFO,
    { title = "Folds", id = "dojo_fold_level" }
  )
end

local function set_level(level)
  vim.wo.foldenable = true
  vim.wo.foldlevel = math.max(0, level)
  level_info(vim.wo.foldlevel)
end

function M.overview()
  set_level(0)
end

function M.deeper()
  -- foldlevel is 99 when everything is open; start stepping from the top.
  local current = vim.wo.foldenable and vim.wo.foldlevel or 0
  set_level(current >= 50 and 1 or current + 1)
end

function M.shallower()
  local current = vim.wo.foldenable and vim.wo.foldlevel or 0
  set_level(current >= 50 and 0 or current - 1)
end

function M.unfold_all()
  vim.wo.foldenable = true
  vim.wo.foldlevel = 99
  vim.notify("All folds open", vim.log.levels.INFO, { title = "Folds", id = "dojo_fold_level" })
end

local function has_parser(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  return ok and parser ~= nil
end

-- Treesitter folds when the language has a parser; otherwise indentation, so
-- folding works in every file right away (a missing parser installs itself).
function M.apply(win)
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "" or vim.api.nvim_win_get_config(win).relative ~= "" then
    return
  end
  if has_parser(buf) then
    if vim.wo[win].foldmethod ~= "expr" then
      vim.wo[win].foldmethod = "expr"
      vim.wo[win].foldexpr = "v:lua.vim.treesitter.foldexpr()"
    end
  else
    vim.wo[win].foldmethod = "indent"
  end
end

function M.refresh()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    M.apply(win)
  end
end

-- Enter on a closed fold opens it one level (in normal file buffers only).
function M.enter()
  if vim.bo.buftype == "" and vim.fn.foldclosed(".") ~= -1 then
    return "zo"
  end
  return "<CR>"
end

function M.setup()
  vim.opt.foldenable = true
  vim.opt.foldlevel = 99
  vim.opt.foldlevelstart = 99

  vim.keymap.set("n", "<CR>", M.enter, { expr = true, desc = "Open fold (on a closed fold)" })

  local group = vim.api.nvim_create_augroup("DojoFolds", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function()
      vim.schedule(M.refresh) -- after LazyVim's own FileType setup
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      M.apply(vim.api.nvim_get_current_win())
      if vim.bo[ev.buf].buftype ~= "" or vim.b[ev.buf].dojo_folded then
        return
      end
      vim.b[ev.buf].dojo_folded = true
      if vim.api.nvim_buf_line_count(ev.buf) > M.big_file then
        -- Wait for treesitter to compute folds, then show the outline.
        vim.defer_fn(function()
          if vim.api.nvim_get_current_buf() == ev.buf and vim.v.exiting == vim.NIL then
            vim.wo.foldenable = true
            vim.wo.foldlevel = 0
          end
        end, 50)
      end
    end,
  })
end

return M
