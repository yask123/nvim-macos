-- A pull request's diff, parsed. Every hunk gets an id like f3h2 (file 3,
-- hunk 2): the reading (reading.lua) points at code with these.

local M = {}

-- Files nobody reads line by line: shown, but summarised for the reading.
local mechanical = {
  "%.lock$",
  "%-lock%.json$",
  "%-lock%.yaml$",
  "go%.sum$",
  "%.min%.js$",
  "%.min%.css$",
  "%.map$",
  "%.snap$",
  "%.svg$",
  "%.pbxproj$",
  "^dist/",
  "/dist/",
  "^vendor/",
  "/vendor/",
  "/node_modules/",
  "%.generated%.",
  "_pb2%.py$",
  "%.pb%.go$",
}

function M.is_mechanical(path)
  for _, pattern in ipairs(mechanical) do
    if path:find(pattern) then
      return true
    end
  end
  return false
end

---@param text string  the output of `gh pr diff`
function M.parse(text)
  local files, hunks = {}, {}
  local file, hunk
  local old_line, new_line = 0, 0

  local function close_hunk()
    hunk = nil
  end

  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local a, b = line:match("^diff %-%-git a/(.-) b/(.+)$")
    if a then
      close_hunk()
      file = {
        index = #files + 1,
        path = b,
        old_path = a,
        status = a ~= b and "renamed" or "modified",
        hunks = {},
        additions = 0,
        deletions = 0,
      }
      files[#files + 1] = file
    elseif file and not hunk and line:match("^new file mode") then
      file.status = "added"
    elseif file and not hunk and line:match("^deleted file mode") then
      file.status = "deleted"
    elseif file and not hunk and line:match("^rename to ") then
      file.status = "renamed"
      file.path = line:match("^rename to (.+)$")
    elseif file and not hunk and line:match("^Binary files ") then
      file.binary = true
    elseif file and line:match("^@@ ") then
      local old_start, new_start, context = line:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@ ?(.*)$")
      hunk = {
        id = ("f%dh%d"):format(file.index, #file.hunks + 1),
        file = file,
        context = context or "",
        old_start = tonumber(old_start) or 1,
        new_start = tonumber(new_start) or 1,
        lines = {},
        additions = 0,
        deletions = 0,
      }
      old_line, new_line = hunk.old_start, hunk.new_start
      file.hunks[#file.hunks + 1] = hunk
      hunks[hunk.id] = hunk
    elseif hunk then
      local kind = line:sub(1, 1)
      if kind == "+" then
        hunk.lines[#hunk.lines + 1] = { kind = "+", text = line:sub(2), new = new_line }
        new_line = new_line + 1
        hunk.additions = hunk.additions + 1
        file.additions = file.additions + 1
      elseif kind == "-" then
        hunk.lines[#hunk.lines + 1] = { kind = "-", text = line:sub(2), old = old_line }
        old_line = old_line + 1
        hunk.deletions = hunk.deletions + 1
        file.deletions = file.deletions + 1
      elseif kind == " " or line == "" then
        hunk.lines[#hunk.lines + 1] = { kind = " ", text = line:sub(2), old = old_line, new = new_line }
        old_line = old_line + 1
        new_line = new_line + 1
      end -- "\ No newline at end of file" and anything else: not code
    end
  end

  -- A trailing empty context line is the split's artefact, not part of the hunk.
  for _, f in ipairs(files) do
    for _, h in ipairs(f.hunks) do
      local last = h.lines[#h.lines]
      if last and last.kind == " " and last.text == "" then
        h.lines[#h.lines] = nil
      end
    end
    f.mechanical = M.is_mechanical(f.path)
  end

  local additions, deletions = 0, 0
  for _, f in ipairs(files) do
    additions, deletions = additions + f.additions, deletions + f.deletions
  end
  return { files = files, hunks = hunks, additions = additions, deletions = deletions }
end

--- The diff as the reading sees it: hunks labelled, mechanical files and
--- very long hunks shortened, the whole thing within `budget` characters.
function M.prompt(diff, budget)
  budget = budget or 120000
  local out, size = {}, 0
  local function add(text)
    out[#out + 1] = text
    size = size + #text + 1
  end
  for _, file in ipairs(diff.files) do
    local note = file.status ~= "modified" and (" (" .. file.status .. ")") or ""
    add(("## f%d %s%s  +%d -%d"):format(file.index, file.path, note, file.additions, file.deletions))
    if file.binary then
      add("(binary)")
    elseif file.mechanical then
      add("(mechanical: not shown)")
    else
      for _, hunk in ipairs(file.hunks) do
        add(("### %s @@ %s"):format(hunk.id, hunk.context))
        local limit = size > budget and 0 or 160
        for index, line in ipairs(hunk.lines) do
          if index > limit then
            add(("… %d more lines"):format(#hunk.lines - limit))
            break
          end
          add(line.kind .. line.text)
        end
      end
    end
    add("")
  end
  return table.concat(out, "\n")
end

return M
