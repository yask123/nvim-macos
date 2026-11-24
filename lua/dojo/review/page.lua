-- The review page: what the pull request is, the trace, the step you're on
-- read out, and the diff in reading order. One buffer of text and colour.

local M = {}

local draw = require("dojo.draw")
local trace = require("dojo.review.trace")

local MARGIN = "   "

-- push(line, text, group, text, group, …); a nil group is plain text.
local function push(line, ...)
  for index = 1, select("#", ...), 2 do
    local text, group = select(index, ...)
    draw.push(line, text, group)
  end
  return line
end

local function row(...)
  return push(draw.line(), MARGIN, nil, ...)
end

local function rule(title, width, tail)
  local line = row("── ", "DojoReviewRail", title, "DojoReviewHeading", " ", nil)
  local used = draw.width(line.text) + (tail and draw.width(tail.text) or 0)
  draw.push(line, string.rep("─", math.max(4, width - used - 2)), "DojoReviewRail")
  if tail then
    draw.push(line, " ", nil)
    for _, mark in ipairs(tail.marks) do
      table.insert(line.marks, { mark[1] + #line.text, mark[2] + #line.text, mark[3] })
    end
    line.text = line.text .. tail.text
  end
  return line
end

local function checks(pr)
  local rollup = type(pr.statusCheckRollup) == "table" and pr.statusCheckRollup or {}
  if #rollup == 0 then
    return nil
  end
  local failed, running = 0, 0
  for _, check in ipairs(rollup) do
    local conclusion, status = (check.conclusion or check.state or ""):upper(), (check.status or ""):upper()
    if conclusion == "FAILURE" or conclusion == "ERROR" or conclusion == "TIMED_OUT" or conclusion == "CANCELLED" then
      failed = failed + 1
    elseif (status ~= "" and status ~= "COMPLETED") or conclusion == "PENDING" or conclusion == "EXPECTED" then
      running = running + 1
    end
  end
  if failed > 0 then
    return ("%d check%s failing"):format(failed, failed == 1 and "" or "s"), "DojoReviewRemoved"
  elseif running > 0 then
    return "checks running", "DojoReviewChanged"
  end
  return "checks pass", "DojoReviewAdded"
end

local function counts(line, additions, deletions)
  if additions > 0 then
    draw.push(line, "+" .. additions, "DojoReviewAdded")
  end
  if deletions > 0 then
    draw.push(line, (additions > 0 and " " or "") .. "−" .. deletions, "DojoReviewRemoved")
  end
end

--- The rows of the "Read" section: per chapter, one row per file.
function M.reading_order(state)
  local reading = state.reading or require("dojo.review.reading").plain(state.diff)
  local chapters = {}
  for _, chapter in ipairs(reading.chapters) do
    local rows, by_file = {}, {}
    for _, id in ipairs(chapter.hunks) do
      local hunk = state.diff.hunks[id]
      local entry = by_file[hunk.file.index]
      if not entry then
        entry = { file = hunk.file, hunks = {}, additions = 0, deletions = 0 }
        by_file[hunk.file.index] = entry
        rows[#rows + 1] = entry
      end
      entry.hunks[#entry.hunks + 1] = id
      entry.additions = entry.additions + hunk.additions
      entry.deletions = entry.deletions + hunk.deletions
      entry.note = entry.note or (reading.notes or {})[id]
    end
    chapters[#chapters + 1] = { title = chapter.title, attention = chapter.attention, rows = rows }
  end
  -- Files with no hunks at all (binary, mechanical and empty): still listed.
  local listed = {}
  for _, chapter in ipairs(chapters) do
    for _, entry in ipairs(chapter.rows) do
      listed[entry.file.index] = true
    end
  end
  local rest = {}
  for _, file in ipairs(state.diff.files) do
    if not listed[file.index] then
      rest[#rest + 1] = { file = file, hunks = {}, additions = file.additions, deletions = file.deletions }
    end
  end
  if #rest > 0 then
    chapters[#chapters + 1] = { title = "No text to show", attention = "skip", rows = rest }
  end
  return chapters
end

---@return { lines: table[], targets: table<integer, table>, trace_top: integer?, steps: table?, visible: integer[]? }
function M.build(state, width)
  local pr, diff, reading = state.pr, state.diff, state.reading
  local lines, targets = {}, {}
  local function add(line)
    lines[#lines + 1] = line or draw.line()
    return #lines
  end
  local inner = math.max(60, width - #MARGIN * 2)

  -- What it is.
  add()
  local top = row(
    ("#%d"):format(pr.number),
    "DojoReviewAccent",
    "  ",
    nil,
    ("%s/%s"):format(pr.owner or "?", pr.repo or "?"),
    "DojoReviewQuiet"
  )
  local facts = draw.line()
  local check_text, check_group = checks(pr)
  if check_text then
    draw.push(facts, check_text, check_group)
    draw.push(facts, "  ·  ", "DojoReviewRail")
  end
  counts(facts, diff.additions, diff.deletions)
  draw.push(facts, "  ·  ", "DojoReviewRail")
  draw.push(facts, ("%d file%s"):format(#diff.files, #diff.files == 1 and "" or "s"), "DojoReviewQuiet")
  if pr.isDraft then
    draw.push(facts, "  ·  draft", "DojoReviewQuiet")
  elseif pr.state and pr.state ~= "OPEN" then
    draw.push(facts, "  ·  " .. pr.state:lower(), "DojoReviewQuiet")
  end
  local gap = math.max(2, inner - draw.width(top.text) + #MARGIN - draw.width(facts.text))
  draw.push(top, string.rep(" ", gap), nil)
  for _, mark in ipairs(facts.marks) do
    table.insert(top.marks, { mark[1] + #top.text, mark[2] + #top.text, mark[3] })
  end
  top.text = top.text .. facts.text
  add(top)
  add(row(reading and reading.headline and reading.headline ~= "" and reading.headline or pr.title, "DojoReviewTitle"))
  if reading and reading.headline and reading.headline ~= "" and reading.headline ~= pr.title then
    add(row(pr.title, "DojoReviewQuiet"))
  end
  add(
    row(
      vim.tbl_get(pr, "author", "login") or "someone",
      "DojoReviewPart",
      "  ",
      nil,
      (pr.headRefName or "?"),
      "DojoReviewQuiet",
      " → ",
      "DojoReviewRail",
      (pr.baseRefName or "?"),
      "DojoReviewQuiet"
    )
  )
  add()

  -- Before / now / how: three short lines, when there is a reading.
  if reading and not reading.plain then
    for _, pair in ipairs({ { "Before", reading.was }, { "Now", reading.now }, { "How", reading.how } }) do
      if pair[2] and pair[2] ~= "" then
        add(
          row(
            draw.fit(pair[1], 8),
            "DojoReviewQuiet",
            pair[2],
            pair[1] == "Now" and "DojoReviewText" or "DojoReviewPart"
          )
        )
      end
    end
    add()
  end

  -- The trace.
  local result = { lines = lines, targets = targets }
  local tellings = draw.line()
  for _, pair in ipairs({ { "diff", "d" }, { "before", "b" }, { "after", "a" } }) do
    local on = state.telling == pair[1]
    draw.push(tellings, pair[2] .. " ", on and "DojoReviewFocus" or "DojoReviewRail")
    draw.push(tellings, pair[1] .. "   ", on and "DojoReviewFocus" or "DojoReviewQuiet")
  end
  if reading and not reading.plain then
    add(rule("Trace", inner, tellings))
    add()
    local drawn =
      trace.draw(reading, { width = inner, telling = state.telling, focus = state.focus, reveal = state.reveal })
    result.trace_top = #lines + 1
    result.steps, result.visible = drawn.steps, drawn.visible
    for _, line in ipairs(drawn.lines) do
      local shifted = draw.line()
      draw.push(shifted, MARGIN, nil)
      for _, mark in ipairs(line.marks) do
        table.insert(shifted.marks, { mark[1] + #MARGIN, mark[2] + #MARGIN, mark[3] })
      end
      shifted.text = shifted.text .. line.text
      add(shifted)
    end
    add()
    -- The step in focus, read out: who, what, what travels, what kind of change.
    local step = reading.flow[state.focus or 0]
    if step then
      local names = {}
      for _, part in ipairs(reading.cast) do
        names[part.id] = part.name
      end
      local status_word = ({
        added = "new in this PR",
        changed = "changed",
        removed = "gone after this PR",
        same = "as before",
      })[step.status]
      local status_group = ({
        added = "DojoReviewAdded",
        changed = "DojoReviewChanged",
        removed = "DojoReviewRemoved",
        same = "DojoReviewQuiet",
      })[step.status]
      local line = row(("%02d"):format(state.focus), "DojoReviewFocus", "  ", nil)
      if step.from ~= step.to then
        draw.push(line, names[step.from] .. " → ", "DojoReviewQuiet")
      end
      draw.push(line, names[step.to], "DojoReviewPart")
      draw.push(line, "  " .. step.does, "DojoReviewText")
      if step.data ~= "" then
        draw.push(line, "  ⟨" .. step.data .. "⟩", "DojoReviewQuiet")
      end
      draw.push(line, "    " .. status_word, status_group)
      targets[add(line)] = step.hunk and { hunk = step.hunk } or nil
      local detail = row("    ", nil)
      if step.status == "changed" and step.was ~= "" then
        draw.push(detail, "before: " .. step.was, "DojoReviewQuiet")
      end
      if reading.breaks == (state.focus - 1) and (reading.pain or "") ~= "" and state.telling ~= "after" then
        draw.push(detail, (detail.text:match("%S") and "   " or "") .. "✕ " .. reading.pain, "DojoReviewRemoved")
      end
      if step.hunk then
        local hunk = diff.hunks[step.hunk]
        draw.push(detail, (detail.text:match("%S") and "   " or "") .. hunk.file.path, "DojoReviewQuiet")
        draw.push(detail, "  ↩ read the code", "DojoReviewRail")
      end
      if detail.text:match("%S") then
        targets[add(detail)] = step.hunk and { hunk = step.hunk } or nil
      end
    end
    add()
  elseif state.reading_state == "reading" then
    add(rule("Trace", inner))
    add()
    add(row("Claude is reading the change" .. string.rep(".", (state.tick or 0) % 4), "DojoReviewPart"))
    add(row("The trace draws itself here in a few seconds. The files below are ready now.", "DojoReviewQuiet"))
    add()
  elseif state.reading_state == "failed" then
    add(rule("Trace", inner))
    add()
    add(row("No trace this time: " .. (state.problem or "something went wrong") .. ".", "DojoReviewChanged"))
    add(row("Press r to try again. The files below are in the pull request's own order.", "DojoReviewQuiet"))
    add()
  elseif state.reading_state == "none" then
    add(rule("Trace", inner))
    add()
    add(row("Claude draws this part: the change as one line through the system.", "DojoReviewPart"))
    add(
      row(
        "It needs Claude Code (the `claude` command) or an API key in ANTHROPIC_API_KEY. Press r once one is there.",
        "DojoReviewQuiet"
      )
    )
    add()
  end

  -- The diff in reading order.
  add(rule(reading and not reading.plain and "Read, in this order" or "Files", inner))
  add()
  local chapters = M.reading_order(state)
  local path_width = 0
  for _, chapter in ipairs(chapters) do
    for _, entry in ipairs(chapter.rows) do
      path_width = math.max(path_width, draw.width(entry.file.path))
    end
  end
  path_width = math.min(path_width, math.max(30, inner - 46))
  local number = 0
  for _, chapter in ipairs(chapters) do
    local attention_group = ({ focus = "DojoReviewText", skim = "DojoReviewPart", skip = "DojoReviewQuiet" })[chapter.attention]
    local head = row(
      draw.fit(chapter.attention, 7),
      chapter.attention == "focus" and "DojoReviewAccent" or "DojoReviewRail",
      chapter.title,
      attention_group
    )
    add(head)
    for _, entry in ipairs(chapter.rows) do
      number = number + 1
      local dim = chapter.attention == "skip"
      local line = row(draw.fit("", 7), nil)
      local path = entry.file.path
      if draw.width(path) > path_width then
        path = "…" .. vim.fn.strcharpart(path, vim.fn.strchars(path) - path_width + 1)
      end
      local dir, name = path:match("^(.*/)([^/]*)$")
      if dir then
        draw.push(line, dir, "DojoReviewQuiet")
        draw.push(line, name, dim and "DojoReviewQuiet" or "DojoReviewText")
      else
        draw.push(line, path, dim and "DojoReviewQuiet" or "DojoReviewText")
      end
      draw.push(line, string.rep(" ", path_width - draw.width(path) + 3), nil)
      local before = draw.width(line.text)
      counts(line, entry.additions, entry.deletions)
      if entry.file.status == "added" then
        draw.push(line, "  new", "DojoReviewAdded")
      elseif entry.file.status == "deleted" then
        draw.push(line, "  deleted", "DojoReviewRemoved")
      elseif entry.file.status == "renamed" then
        draw.push(line, "  renamed", "DojoReviewChanged")
      end
      draw.push(line, string.rep(" ", math.max(2, 18 - (draw.width(line.text) - before))), nil)
      local comments = state.comment_count and state.comment_count(entry.file.path) or 0
      if entry.note then
        draw.push(line, entry.note, "DojoReviewPart")
      end
      if comments > 0 then
        draw.push(line, ("   %d comment%s"):format(comments, comments == 1 and "" or "s"), "DojoReviewChanged")
      end
      local index = add(line)
      if #entry.hunks > 0 then
        targets[index] = { hunk = entry.hunks[1], hunks = entry.hunks }
      end
    end
    add()
  end

  -- Keys, quietly.
  local pending = state.pending and #state.pending or 0
  local keys = row()
  local function key(name, what)
    draw.push(keys, name, "DojoReviewPart")
    draw.push(keys, " " .. what .. "   ", "DojoReviewRail")
  end
  if reading and not reading.plain then
    key("h l", "step")
  end
  key("↩", "read the code")
  key(
    "S",
    pending > 0 and ("send review (%d comment%s waiting)"):format(pending, pending == 1 and "" or "s") or "send review"
  )
  key("o", "open on GitHub")
  key("r", "read again")
  key("q", "close")
  add(keys)
  add()
  return result
end

return M
