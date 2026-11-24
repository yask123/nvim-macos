-- Reading the code of a pull request: one file's changes in one buffer,
-- coloured like the language they're written in. Added lines carry a green
-- wash, removed lines a rose one; the gutter shows each line's number in the
-- file and a + or −. Comments sit under the line they are about.

local M = {}

local draw = require("dojo.draw")
local ns = vim.api.nvim_create_namespace("dojo_review_code")
local ns_notes = vim.api.nvim_create_namespace("dojo_review_notes")

-- buffer → { [line] = { kind, old, new, hunk } }
local meta = {}

--- The gutter ('statuscolumn'): the line's number in the file, then + or −.
function M.gutter()
  local buf = vim.api.nvim_get_current_buf()
  if vim.g.statusline_winid and vim.api.nvim_win_is_valid(vim.g.statusline_winid) then
    buf = vim.api.nvim_win_get_buf(vim.g.statusline_winid)
  end
  if vim.v.virtnum ~= 0 then
    return "        "
  end
  return M.gutter_for(buf, vim.v.lnum)
end

function M.gutter_for(buf, lnum)
  local info = meta[buf] and meta[buf][lnum]
  if not info then
    return "        "
  end
  -- The number stays quiet; the sign carries the colour.
  local number = info.kind == "-" and info.old or info.new
  local group = info.kind == "+" and "DojoReviewAdded" or info.kind == "-" and "DojoReviewRemoved" or "DojoReviewRail"
  local sign = info.kind == "+" and "+" or info.kind == "-" and "−" or " "
  return ("%%#DojoReviewQuiet#%5s %%#%s#%s %%*"):format(number or "", group, sign)
end

local function wrap(text, width)
  local out = {}
  for _, paragraph in ipairs(vim.split(text, "\n", { plain = true })) do
    local line = ""
    for word in paragraph:gmatch("%S+") do
      if line ~= "" and draw.width(line) + 1 + draw.width(word) > width then
        out[#out + 1] = line
        line = word
      else
        line = line == "" and word or (line .. " " .. word)
      end
    end
    out[#out + 1] = line
  end
  return out
end

-- A comment thread as lines under its code line.
local function comment_lines(author, body, group, width)
  local lines = {}
  for index, text in ipairs(wrap(body, width - 6)) do
    lines[#lines + 1] = {
      { "    ", "Normal" },
      { index == 1 and "│ " or "│ ", "DojoReviewRail" },
      { index == 1 and (author .. "  ") or "", "DojoReviewPart" },
      { text, group },
    }
  end
  return lines
end

--- The buffer line a comment on (path side, line) belongs to, if it is shown.
local function line_for(buf, side, number)
  for index, info in ipairs(meta[buf] or {}) do
    if side == "LEFT" and info.kind == "-" and info.old == number then
      return index
    elseif side ~= "LEFT" and info.kind ~= "-" and info.new == number then
      return index
    end
  end
end

--- Draw comments (GitHub's threads and your waiting ones) under their lines.
function M.annotate(state, buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns_notes, 0, -1)
  local file = state.code_files and state.code_files[buf]
  if not file then
    return
  end
  local width = 96
  local at = {} ---@type table<integer, table[]>
  for _, thread in ipairs(state.threads or {}) do
    if thread.path == file.path and not thread.resolved then
      local line = line_for(buf, thread.side, thread.line)
      if line then
        at[line] = at[line] or {}
        for _, comment in ipairs(thread.comments) do
          vim.list_extend(at[line], comment_lines(comment.author, comment.body, "DojoReviewText", width))
        end
      end
    end
  end
  for _, comment in ipairs(state.pending or {}) do
    if comment.path == file.path then
      local line = line_for(buf, comment.side, comment.line)
      if line then
        at[line] = at[line] or {}
        vim.list_extend(at[line], comment_lines("you (not sent yet)", comment.body, "DojoReviewChanged", width))
      end
    end
  end
  for line, virt in pairs(at) do
    table.insert(virt, { { "", "Normal" } })
    vim.api.nvim_buf_set_extmark(buf, ns_notes, line - 1, 0, { virt_lines = virt })
  end
end

--- Build (once) the buffer that shows a file's changes.
function M.buffer(state, file)
  state.code_bufs = state.code_bufs or {}
  state.code_files = state.code_files or {}
  local existing = state.code_bufs[file.index]
  if existing and vim.api.nvim_buf_is_valid(existing) then
    return existing
  end
  local buf = vim.api.nvim_create_buf(false, true)
  state.code_bufs[file.index] = buf
  state.code_files[buf] = file
  local lines, info = {}, {}
  local heads = {} -- line → hunk (its first line)
  for _, hunk in ipairs(file.hunks) do
    heads[#lines + 1] = hunk
    for _, line in ipairs(hunk.lines) do
      lines[#lines + 1] = line.text
      info[#lines] = { kind = line.kind, old = line.old, new = line.new, hunk = hunk.id }
    end
  end
  if #lines == 0 then
    lines = { file.binary and "(a binary file: nothing to read)" or "(no text changed: renamed, or permissions only)" }
  end
  meta[buf] = info
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].buftype = "nofile"
  vim.b[buf].completion = false
  pcall(
    vim.api.nvim_buf_set_name,
    buf,
    ("review://%s/%s#%d/%s"):format(state.pr.owner or "", state.pr.repo or "", state.pr.number, file.path)
  )
  -- The file's own language colours the code (no language server: this isn't the file itself).
  local filetype = vim.filetype.match({ filename = file.path, contents = lines })
  if filetype then
    local language = vim.treesitter.language.get_lang(filetype) or filetype
    if not pcall(vim.treesitter.start, buf, language) then
      vim.bo[buf].syntax = filetype
    end
  end
  for index, line in pairs(info) do
    if line.kind == "+" then
      vim.api.nvim_buf_set_extmark(buf, ns, index - 1, 0, { line_hl_group = "DojoReviewAddedLine" })
    elseif line.kind == "-" then
      vim.api.nvim_buf_set_extmark(buf, ns, index - 1, 0, { line_hl_group = "DojoReviewRemovedLine" })
    end
  end
  -- Above each hunk: where it is, and what the reading says it does.
  local notes = state.reading and state.reading.notes or {}
  local steps = {}
  for index, step in ipairs(state.reading and state.reading.flow or {}) do
    if step.hunk then
      steps[step.hunk] = steps[step.hunk] or {}
      table.insert(steps[step.hunk], ("%02d %s"):format(index, step.does))
    end
  end
  for line, hunk in pairs(heads) do
    local head = { { "        ", "Normal" }, { "── ", "DojoReviewRail" } }
    if hunk.context ~= "" then
      head[#head + 1] = { vim.trim(hunk.context) .. " ", "DojoReviewQuiet" }
    else
      head[#head + 1] = { ("line %d "):format(hunk.new_start), "DojoReviewQuiet" }
    end
    if notes[hunk.id] then
      head[#head + 1] = { "· " .. notes[hunk.id] .. " ", "DojoReviewPart" }
    end
    if steps[hunk.id] then
      head[#head + 1] = { "· step " .. table.concat(steps[hunk.id], ", ") .. " ", "DojoReviewAccent" }
    end
    local virt = { head }
    if line > 1 then
      table.insert(virt, 1, { { "", "Normal" } })
    end
    vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, { virt_lines = virt, virt_lines_above = true })
  end
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      meta[buf] = nil
    end,
  })
  M.annotate(state, buf)
  return buf
end

--- The first buffer line of a hunk.
function M.line_of(buf, hunk_id)
  for index, info in ipairs(meta[buf] or {}) do
    if info.hunk == hunk_id then
      return index
    end
  end
  return 1
end

--- What a buffer line is: the path, the side and line number a comment would
--- attach to, and its hunk.
function M.at(state, buf, line)
  local info = meta[buf] and meta[buf][line]
  local file = state.code_files and state.code_files[buf]
  if not info or not file then
    return nil
  end
  return {
    path = file.path,
    side = info.kind == "-" and "LEFT" or "RIGHT",
    line = info.kind == "-" and info.old or info.new,
    hunk = info.hunk,
    kind = info.kind,
  }
end

--- The first line of the next (or previous) run of changed lines.
function M.next_change(buf, from, direction)
  local info = meta[buf] or {}
  local count = #info
  local line = from
  local function changed(index)
    return info[index] and info[index].kind ~= " "
  end
  -- Leave the run the cursor is in, then find the start of the next one.
  while line >= 1 and line <= count and changed(line) do
    line = line + direction
  end
  while line >= 1 and line <= count and not changed(line) do
    line = line + direction
  end
  if line < 1 or line > count then
    return nil
  end
  if direction < 0 then
    while line > 1 and changed(line - 1) do
      line = line - 1
    end
  end
  return line
end

--- Window options that make a diff buffer read well.
function M.dress(win)
  local wo = vim.wo[win]
  wo.statuscolumn = "%!v:lua.require'dojo.review.code'.gutter()"
  wo.number, wo.relativenumber = false, false
  wo.signcolumn, wo.foldcolumn = "no", "0"
  wo.cursorline = true
  wo.wrap = false
  wo.list = false
  wo.spell = false
  wo.foldenable = false
  wo.conceallevel = 0
end

return M
