-- The trace: one request drawn as a single line through the system.
--
-- Every part the request touches is a rail (a row). Time runs left to right,
-- one column per step. The line runs along a rail and turns onto another
-- where a step hands over. Its colour is the diff: quiet where nothing
-- changed, green where the step is new, amber where it changed, a dashed
-- rose ghost where it is gone, ✕ where it used to go wrong.
--
-- Pure layout: `draw` takes a reading and returns lines of text with colour
-- spans (lua/dojo/draw.lua shape). No buffers, no windows; tested headless.

local M = {}

local draw = require("dojo.draw")

-- Rows per rail: a label row above it, the rail, a gap below.
local ROWS = 3

local glyph = {
  h = "─",
  v = "│",
  h_gone = "╌",
  v_gone = "╎",
  h_hop = "┄",
  v_hop = "┆",
  rail = "·",
  dot = "●",
  dot_focus = "◉",
  dot_gone = "○",
  broke = "✕",
  start = "○",
}

local status_group = {
  same = "DojoReviewSame",
  added = "DojoReviewAdded",
  changed = "DojoReviewChanged",
  removed = "DojoReviewRemoved",
}

--- The steps a telling shows: "before" has no added steps, "after" no removed ones.
function M.visible(reading, telling)
  local steps = {}
  for index, step in ipairs(reading.flow) do
    local show = telling == "diff"
      or (telling == "before" and step.status ~= "added")
      or (telling == "after" and step.status ~= "removed")
    if show then
      steps[#steps + 1] = index
    end
  end
  return steps
end

local function chars(text)
  return vim.fn.split(text, "\\zs")
end

---@param reading table
---@param opts { width: integer, telling?: string, focus?: integer, reveal?: integer }
---@return { lines: table[], steps: table<integer, {row: integer, col: integer}>, visible: integer[] }
function M.draw(reading, opts)
  local telling = opts.telling or "diff"
  local visible = M.visible(reading, telling)
  local cast = reading.cast
  local rail_of = {}
  for index, part in ipairs(cast) do
    rail_of[part.id] = index
  end

  -- Columns: names on the left, then one cell of `step_width` per step.
  local name_width = 4
  for _, part in ipairs(cast) do
    name_width = math.max(name_width, draw.width(part.name))
  end
  name_width = math.min(name_width, 24)
  local x0 = name_width + 6
  local count = math.max(#visible, 1)
  local step_width = math.max(11, math.min(22, math.floor((opts.width - x0 - 4) / count)))
  local half = math.floor(step_width / 2)
  local width = x0 + 2 + count * step_width + 2
  local height = #cast * ROWS + 1

  -- The canvas: one cell per character.
  local canvas = {}
  for row = 1, height do
    canvas[row] = {}
  end
  local function put(row, col, char, group)
    if row >= 1 and row <= height and col >= 1 and col <= width then
      canvas[row][col] = { char, group }
    end
  end
  local function write(row, col, text, group)
    for offset, char in ipairs(chars(text)) do
      put(row, col + offset - 1, char, group)
    end
  end
  local function rail_row(rail)
    return (rail - 1) * ROWS + 2
  end
  local function step_x(position)
    return x0 + 2 + half + (position - 1) * step_width
  end

  -- Rails: the part's name, then a faint dotted line to run along.
  for index, part in ipairs(cast) do
    local row = rail_row(index)
    local name_group = part.change == "added" and "DojoReviewAdded"
      or part.change == "changed" and "DojoReviewPart"
      or "DojoReviewQuiet"
    local name = draw.fit(part.name, name_width):gsub("%s+$", "")
    write(row, 1 + name_width - draw.width(name), name, name_group) -- right-aligned against the rail
    if part.kind == "guard" then
      put(row, name_width + 3, "◇", "DojoReviewQuiet") -- a part that can stop the request
    elseif part.change == "added" then
      put(row, name_width + 3, "+", "DojoReviewAdded")
    end
    for col = x0, width - 1, 3 do
      put(row, col, glyph.rail, "DojoReviewRail")
    end
  end

  -- An orthogonal run of the line through waypoints { x, row }, each stretch
  -- in its own style. Corners are rounded.
  local function route(points, styles)
    for index = 1, #points - 1 do
      local a, b, style = points[index], points[index + 1], styles[index]
      if a[2] == b[2] then
        for col = math.min(a[1], b[1]), math.max(a[1], b[1]) do
          put(a[2], col, style.h, style.group)
        end
      else
        for row = math.min(a[2], b[2]), math.max(a[2], b[2]) do
          put(row, a[1], style.v, style.group)
        end
      end
    end
    for index = 2, #points - 1 do
      local before, here, after = points[index - 1], points[index], points[index + 1]
      local style = styles[index]
      local char
      if before[2] == here[2] and after[1] == here[1] then -- along a rail, then up or down
        char = after[2] > here[2] and "╮" or "╯"
      elseif before[1] == here[1] and after[2] == here[2] then -- up or down, then along a rail
        char = before[2] < here[2] and "╰" or "╭"
      end
      if char then
        put(here[2], here[1], char, style.group)
      end
    end
  end

  local function style_for(step)
    local status = telling == "before" and "same" or step.status
    if telling == "after" and status == "removed" then
      status = "same"
    end
    local group = status_group[status]
    if status == "removed" then
      return { h = glyph.h_gone, v = glyph.v_gone, group = group }
    end
    return { h = glyph.h, v = glyph.v, group = group }
  end
  local hop = { h = glyph.h_hop, v = glyph.v_hop, group = "DojoReviewRail" }

  local reveal = opts.reveal or #visible
  local steps = {}
  local at -- where the line is: { x, row }
  local dots = {}
  local labels = {}
  for position, index in ipairs(visible) do
    if position > reveal then
      break
    end
    local step = reading.flow[index]
    local following = reading.flow[visible[position + 1] or 0]
    local from_row, to_row = rail_row(rail_of[step.from]), rail_row(rail_of[step.to])
    local x = step_x(position)
    local turn = x - half
    local style = style_for(step)
    if not at then
      put(from_row, x0, glyph.start, style.group)
      at = { x0 + 1, from_row }
    end
    -- The line is on another rail than the one this step starts from (a call
    -- returned further up than where it was made): a faint hop takes it there.
    if at[2] ~= from_row then
      local hop_x = turn - 2
      route({ at, { hop_x, at[2] }, { hop_x, from_row }, { hop_x + 1, from_row } }, { hop, hop, hop })
      at = { hop_x + 1, from_row }
    end
    -- A call the caller carries on from is a spur: the line stays on the
    -- caller's rail and a branch reaches the part that was called.
    local spur = from_row ~= to_row and following ~= nil and following.from ~= step.to
    if from_row == to_row then
      route({ at, { x - 1, to_row } }, { style })
      at = { x + 1, to_row }
    elseif spur then
      route({ at, { turn, from_row } }, { style })
      route({ { turn, from_row }, { turn, to_row }, { x - 1, to_row } }, { style, style })
      put(from_row, turn, to_row > from_row and "┬" or "┴", style.group)
      at = { turn + 1, from_row }
    else
      route({ at, { turn, from_row }, { turn, to_row }, { x - 1, to_row } }, { style, style, style })
      at = { x + 1, to_row }
    end

    local focused = opts.focus == index
    local broke = telling ~= "after" and reading.breaks == index - 1
    local mark = broke and glyph.broke
      or (step.status == "removed" and telling == "diff") and glyph.dot_gone
      or focused and glyph.dot_focus
      or glyph.dot
    dots[#dots + 1] =
      { to_row, x, mark, broke and "DojoReviewRemoved" or (focused and "DojoReviewFocus" or style.group) }

    labels[#labels + 1] = {
      row = to_row - 1,
      x = x,
      text = step.does,
      group = focused and "DojoReviewFocus"
        or (step.status ~= "same" and telling ~= "before") and style.group
        or "DojoReviewQuiet",
    }

    -- Step numbers along the bottom.
    write(height, x - 1, ("%02d"):format(index), focused and "DojoReviewFocus" or "DojoReviewRail")

    steps[index] = { row = to_row, col = x }
  end
  for _, dot in ipairs(dots) do
    put(dot[1], dot[2], dot[3], dot[4])
  end

  -- A few words above each dot (the rest is read out below the picture). A
  -- label takes the room the line leaves it: centred on its dot when it can
  -- be, pushed aside by a turn of the line, cut only when there is no room.
  local function taken(row, col)
    local cell = canvas[row] and canvas[row][col]
    return col < x0 or col > width or (cell ~= nil and cell[1] ~= glyph.rail)
  end
  for _, label in ipairs(labels) do
    local left, right = label.x, label.x
    while label.x - left < 26 and not taken(label.row, left - 2) do
      left = left - 1
    end
    while right - label.x < 26 and not taken(label.row, right + 2) do
      right = right + 1
    end
    local room = right - left + 1
    local text = draw.fit(label.text, math.min(room, draw.width(label.text))):gsub("%s+$", "")
    local size = draw.width(text)
    local start = math.max(left, math.min(label.x - math.floor(size / 2), right - size + 1))
    for col = start, start + size - 1 do
      canvas[label.row][col] = nil -- over the rail's dots, never over the line
    end
    write(label.row, start, text, label.group)
  end

  -- Cells → lines with colour spans.
  local lines = {}
  for row = 1, height do
    local line = draw.line()
    local last = 0
    for col = width, 1, -1 do
      if canvas[row][col] then
        last = col
        break
      end
    end
    local run, run_group = "", nil
    local function flush()
      if run ~= "" then
        draw.push(line, run, run_group)
        run = ""
      end
    end
    for col = 1, last do
      local cell = canvas[row][col]
      local char, group = cell and cell[1] or " ", cell and cell[2] or nil
      if group ~= run_group then
        flush()
        run_group = group
      end
      run = run .. char
    end
    flush()
    lines[row] = line
  end
  return { lines = lines, steps = steps, visible = visible, width = width }
end

return M
