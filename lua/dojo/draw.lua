-- Small helpers for Code's own sheets (Open Folder, Settings): build lines of
-- text with coloured spans, then put them in a buffer.

local M = {}

local api = vim.api

function M.width(text)
  return vim.fn.strdisplaywidth(text)
end

--- Exactly `width` cells: cut with … or padded with spaces.
function M.fit(text, width)
  if M.width(text) > width then
    local chars = vim.fn.strchars(text)
    repeat
      chars = chars - 1
      text = vim.fn.strcharpart(text, 0, chars) .. "…"
    until chars <= 1 or M.width(text) <= width
  end
  return text .. string.rep(" ", math.max(0, width - M.width(text)))
end

--- A line being built: its text, and which stretches get which colour.
function M.line()
  return { text = "", marks = {} }
end

function M.push(line, text, group)
  local start = #line.text
  line.text = line.text .. text
  if group then
    table.insert(line.marks, { start, #line.text, group })
  end
end

function M.text(lines)
  return vim.tbl_map(function(line)
    return line.text
  end, lines)
end

--- Colour the buffer's lines as `lines` describe (after their text is set).
function M.paint(buf, ns, lines)
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for index, line in ipairs(lines) do
    for _, mark in ipairs(line.marks) do
      api.nvim_buf_set_extmark(buf, ns, index - 1, mark[1], { end_col = mark[2], hl_group = mark[3] })
    end
  end
end

--- Replace the buffer's text with `lines` and colour it.
function M.put(buf, ns, lines)
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, M.text(lines))
  vim.bo[buf].modifiable = false
  M.paint(buf, ns, lines)
end

function M.color(group, attr)
  return api.nvim_get_hl(0, { name = group, link = false })[attr]
end

return M
