-- The reading: Claude looks at a pull request's diff once and answers with a
-- drawing, not a review. One request's journey through the system, before the
-- change and after it (the trace), and the diff sorted into reading order.
-- "You draw; they think": no risks, no advice, no verdicts.
--
-- Two ways to reach Claude, tried in this order:
--   1. the `claude` command (Claude Code), on the login it already has;
--   2. an API key in ANTHROPIC_API_KEY, over plain HTTPS with curl.
-- With neither, the review still opens: files and diff, no trace.
--
-- Readings are kept per head commit, so a pull request opens instantly the
-- second time and is read again only when it changes.

local M = {}

local VERSION = 2

M.system = [[
You draw pull requests for an engineer who is about to review one. They want to see what it does before reading a line: one request's path through the system, before the change and after it, and the diff in the order worth reading. You draw; they think. You are not reviewing: no risks, no advice, no opinions, no questions. Write almost nothing: short phrases, names exactly as in the code. No praise, no filler, no hedging. If a phrase would fit any pull request, cut it.

Everything you need is in the diff; its hunks are labelled like f3h2 (file 3, hunk 2). Answer straight away.

Every PR answers a problem. A bug fix: what went wrong. A feature: what you couldn't do before. A refactor: what made the code hard to change. Infra or tests: what was fragile or slow.

Fields, in this order:
- headline: what the change does, at most 8 words, starting with a verb. Plain and concrete.
- kind: the dominant kind of change.
- was: the situation before, at most 11 words, as a user or caller experienced it. Not the fix.
- now: the same situation after, at most 11 words.
- how: the key idea of the change, at most 11 words, the way you'd say it at a whiteboard.
- cast: the parts the journey passes through, 3 to 7, in the order it meets them. A part that can stop the request (an access policy, a validator, a rate limiter, a lock) is in the cast whenever the journey reaches it, changed or not. id: a short lowercase handle. name: as written in the code, at most 22 characters (a type, function or file name, never a path), or "You" for the person or outside caller who starts it. kind: person, ui, service, api, store, external (someone else's service), job, config, library or guard (a part whose job is to stop the request: authorization, validation, a limit). role: at most 3 words. change: added (new in this PR), changed (its code changes) or unchanged (context it talks to).
- flow: one request's journey, told once for both versions, in time order, 3 to 8 steps. from and to are cast ids; equal when a part works on its own. does: at most 4 words. data: what travels, at most 3 words, or empty. status: same (happens before and after), removed (only before), added (only after) or changed (both, differently). Only for a changed step, was holds what it did before, at most 5 words; otherwise empty. Only for a step that isn't same, hunk is the id of the hunk where that change lives; otherwise empty. The before journey (same, changed and removed steps) and the after journey (same, changed and added steps) must each read as complete. A check that can stop the request (authorization, validation, a limit) is a step of its own, in the place it happens in the order of execution, even when this PR doesn't touch it: where it sits in the journey is what the reader came to see.
- breaks: the index in flow (starting at 0) of the step where it went wrong before, or -1 when the problem was a step that was missing. pain: at most 6 words, what went wrong there; empty when nothing was wrong (a pure feature).
- chapters: every hunk grouped into 2 to 7 chapters by purpose, in the best reading order. title: a noun phrase of at most 4 words. attention: focus (logic worth reading), skim (wiring, layout, glue) or skip (mechanical: renames, imports, docs, config bumps, lockfiles, boilerplate tests). Each hunk id in exactly one chapter; files shown as "(mechanical: not shown)" have no hunks to list.
- notes: one per hunk in a focus chapter, at most 6 words naming what it does.
]]

M.schema = {
  type = "object",
  additionalProperties = false,
  required = { "headline", "kind", "was", "now", "how", "cast", "flow", "breaks", "pain", "chapters", "notes" },
  properties = {
    headline = { type = "string" },
    kind = {
      type = "string",
      enum = { "feature", "fix", "refactor", "performance", "infra", "tests", "docs", "chore", "mixed" },
    },
    was = { type = "string" },
    now = { type = "string" },
    how = { type = "string" },
    cast = {
      type = "array",
      items = {
        type = "object",
        additionalProperties = false,
        required = { "id", "name", "kind", "role", "change" },
        properties = {
          id = { type = "string" },
          name = { type = "string" },
          kind = {
            type = "string",
            enum = { "person", "ui", "service", "api", "store", "external", "job", "config", "library", "guard" },
          },
          role = { type = "string" },
          change = { type = "string", enum = { "added", "changed", "unchanged" } },
        },
      },
    },
    flow = {
      type = "array",
      items = {
        type = "object",
        additionalProperties = false,
        required = { "from", "to", "does", "data", "status", "was", "hunk" },
        properties = {
          from = { type = "string" },
          to = { type = "string" },
          does = { type = "string" },
          data = { type = "string" },
          status = { type = "string", enum = { "same", "removed", "added", "changed" } },
          was = { type = "string" },
          hunk = { type = "string" },
        },
      },
    },
    breaks = { type = "integer" },
    pain = { type = "string" },
    chapters = {
      type = "array",
      items = {
        type = "object",
        additionalProperties = false,
        required = { "title", "attention", "hunks" },
        properties = {
          title = { type = "string" },
          attention = { type = "string", enum = { "focus", "skim", "skip" } },
          hunks = { type = "array", items = { type = "string" } },
        },
      },
    },
    notes = {
      type = "array",
      items = {
        type = "object",
        additionalProperties = false,
        required = { "hunk", "note" },
        properties = { hunk = { type = "string" }, note = { type = "string" } },
      },
    },
  },
}

local function cache_path(pr)
  local dir = vim.fn.stdpath("cache") .. "/dojo-review"
  vim.fn.mkdir(dir, "p")
  return ("%s/%s__%s__%d__%s.json"):format(
    dir,
    pr.owner or "local",
    pr.repo or "repo",
    pr.number or 0,
    (pr.headRefOid or "head"):sub(1, 12)
  )
end

--- The words Claude is given: the pull request, then its labelled diff.
function M.prompt(pr, diff)
  local body = vim.trim(pr.body or "")
  if #body > 3000 then
    body = body:sub(1, 3000) .. "…"
  end
  return table.concat({
    "# Pull request",
    ("%s/%s #%d: %s"):format(pr.owner or "?", pr.repo or "?", pr.number or 0, pr.title or ""),
    ("%s → %s"):format(pr.headRefName or "?", pr.baseRefName or "?"),
    "",
    "## Description",
    body ~= "" and body or "(none)",
    "",
    "# Diff",
    require("dojo.review.diff").prompt(diff),
  }, "\n")
end

--- Make a reading safe to draw: every id it points at exists, sizes are sane.
---@return table? reading, string? problem
function M.validate(reading, diff)
  if type(reading) ~= "table" or type(reading.cast) ~= "table" or type(reading.flow) ~= "table" then
    return nil, "the answer wasn't a reading"
  end
  local cast, ids = {}, {}
  for _, part in ipairs(reading.cast) do
    if type(part) == "table" and type(part.id) == "string" and part.id ~= "" and not ids[part.id] and #cast < 8 then
      ids[part.id] = true
      part.name = type(part.name) == "string" and part.name ~= "" and part.name or part.id
      cast[#cast + 1] = part
    end
  end
  local flow = {}
  for _, step in ipairs(reading.flow) do
    if type(step) == "table" and ids[step.from] and ids[step.to] and #flow < 10 then
      step.status = ({ same = "same", removed = "removed", added = "added", changed = "changed" })[step.status]
        or "same"
      step.hunk = diff.hunks[step.hunk] and step.hunk or nil
      step.does = type(step.does) == "string" and step.does or ""
      step.data = type(step.data) == "string" and step.data or ""
      step.was = type(step.was) == "string" and step.was or ""
      flow[#flow + 1] = step
    end
  end
  if #cast < 2 or #flow < 2 then
    return nil, "the answer had no journey to draw"
  end
  reading.cast, reading.flow = cast, flow
  reading.breaks = type(reading.breaks) == "number"
      and reading.breaks >= 0
      and reading.breaks < #flow
      and reading.breaks
    or -1

  -- Reading order: each known hunk once; anything left out goes last.
  local seen, chapters = {}, {}
  for _, chapter in ipairs(type(reading.chapters) == "table" and reading.chapters or {}) do
    local hunks = {}
    for _, id in ipairs(type(chapter.hunks) == "table" and chapter.hunks or {}) do
      if diff.hunks[id] and not seen[id] then
        seen[id] = true
        hunks[#hunks + 1] = id
      end
    end
    if #hunks > 0 then
      chapters[#chapters + 1] = {
        title = type(chapter.title) == "string" and chapter.title or "Changes",
        attention = ({ focus = "focus", skim = "skim", skip = "skip" })[chapter.attention] or "skim",
        hunks = hunks,
      }
    end
  end
  local rest = {}
  for _, file in ipairs(diff.files) do
    for _, hunk in ipairs(file.hunks) do
      if not seen[hunk.id] then
        rest[#rest + 1] = hunk.id
      end
    end
  end
  if #rest > 0 then
    chapters[#chapters + 1] =
      { title = #chapters > 0 and "Everything else" or "Changes", attention = "skip", hunks = rest }
  end
  reading.chapters = chapters
  local notes = {}
  for _, note in ipairs(type(reading.notes) == "table" and reading.notes or {}) do
    if type(note) == "table" and diff.hunks[note.hunk] and type(note.note) == "string" then
      notes[note.hunk] = note.note
    end
  end
  reading.notes = notes
  return reading
end

--- Without Claude: the files in the diff's own order, code before the mechanical.
function M.plain(diff)
  local code, mechanical = {}, {}
  for _, file in ipairs(diff.files) do
    for _, hunk in ipairs(file.hunks) do
      table.insert(file.mechanical and mechanical or code, hunk.id)
    end
  end
  local chapters = {}
  if #code > 0 then
    chapters[#chapters + 1] = { title = "Changes", attention = "focus", hunks = code }
  end
  if #mechanical > 0 then
    chapters[#chapters + 1] = { title = "Generated and lock files", attention = "skip", hunks = mechanical }
  end
  return { chapters = chapters, notes = {}, plain = true }
end

--- Which way to Claude there is: "cli", "api" or nil.
function M.engine()
  if vim.env.DOJO_REVIEW_NO_AI == "1" then
    return nil
  end
  if vim.fn.executable("claude") == 1 then
    return "cli"
  end
  if (vim.env.ANTHROPIC_API_KEY or "") ~= "" and vim.fn.executable("curl") == 1 then
    return "api"
  end
  return nil
end

-- The `claude` command prints a list of events; the last holds the answer.
local function from_cli(stdout)
  local ok, data = pcall(vim.json.decode, stdout)
  if not ok then
    return nil, "Claude's answer couldn't be read"
  end
  local result = data
  if vim.islist(data) then
    result = nil
    for _, event in ipairs(data) do
      if type(event) == "table" and event.type == "result" then
        result = event
      end
    end
  end
  if type(result) ~= "table" then
    return nil, "Claude gave no answer"
  end
  if result.is_error then
    return nil, type(result.result) == "string" and result.result or "Claude reported an error"
  end
  if type(result.structured_output) == "table" then
    return result.structured_output
  end
  local decoded, reading = pcall(vim.json.decode, result.result or "")
  if decoded and type(reading) == "table" then
    return reading
  end
  return nil, "Claude's answer wasn't the drawing asked for"
end

local function run_cli(prompt, callback)
  local model = vim.g.dojo_review_model or "sonnet"
  local cmd = {
    "claude",
    "-p",
    "--model",
    model,
    "--output-format",
    "json",
    "--json-schema",
    vim.json.encode(M.schema),
    "--system-prompt",
    M.system,
    "--tools",
    "",
    "--strict-mcp-config",
    "--setting-sources",
    "",
    "--disable-slash-commands",
    "--no-session-persistence",
    "--effort",
    "low",
  }
  -- Run away from the project: the reading needs the diff, not the folder.
  return vim.system(cmd, { text = true, stdin = prompt, timeout = 150000, cwd = vim.uv.os_tmpdir() }, function(result)
    vim.schedule(function()
      if result.code ~= 0 and (result.stdout or "") == "" then
        local err = vim.trim(result.stderr or "")
        if result.signal ~= 0 then
          err = "Claude took too long and was stopped"
        elseif err:find("login") or err:find("auth") then
          err = "Claude Code isn't signed in. Run `claude` in the terminal (⌘T) once."
        end
        return callback(nil, err ~= "" and err or "the claude command failed")
      end
      callback(from_cli(result.stdout or ""))
    end)
  end)
end

-- Claude API over HTTPS. No SDK exists for Lua, so this is the raw request.
local function run_api(prompt, callback)
  local body = vim.json.encode({
    model = vim.g.dojo_review_api_model or "claude-opus-5-5",
    max_tokens = 16000,
    system = M.system,
    messages = { { role = "user", content = prompt } },
    output_config = { effort = "low", format = { type = "json_schema", schema = M.schema } },
    -- If a safety classifier declines, the API retries on a fallback model in the same call.
    fallbacks = "default",
  })
  local cmd = {
    "curl",
    "--silent",
    "--show-error",
    "--max-time",
    "150",
    "https://api.anthropic.com/v1/messages",
    "-H",
    "content-type: application/json",
    "-H",
    "anthropic-version: 2026-10-21",
    "-H",
    "anthropic-beta: server-side-fallback-2026-07-01",
    "-H",
    "@-", -- the key travels on stdin, never in the argument list
    "--data-binary",
    "@" .. vim.fn.tempname(),
  }
  local data_file = cmd[#cmd]:sub(2)
  local file = assert(io.open(data_file, "w"))
  file:write(body)
  file:close()
  return vim.system(cmd, { text = true, stdin = "x-api-key: " .. vim.env.ANTHROPIC_API_KEY .. "\n" }, function(result)
    os.remove(data_file)
    vim.schedule(function()
      if result.code ~= 0 then
        return callback(nil, "Can't reach Claude. Are you offline?")
      end
      local ok, response = pcall(vim.json.decode, result.stdout or "")
      if not ok or type(response) ~= "table" then
        return callback(nil, "Claude's answer couldn't be read")
      end
      if response.type == "error" then
        local kind = vim.tbl_get(response, "error", "type") or ""
        if kind == "authentication_error" then
          return callback(nil, "The key in ANTHROPIC_API_KEY was refused")
        elseif kind == "rate_limit_error" or kind == "overloaded_error" then
          return callback(nil, "Claude is busy right now. Press r to try again.")
        end
        return callback(nil, vim.tbl_get(response, "error", "message") or "Claude reported an error")
      end
      if response.stop_reason == "refusal" then
        return callback(nil, "Claude declined to read this pull request")
      elseif response.stop_reason == "max_tokens" then
        return callback(nil, "The answer was cut short")
      end
      for _, block in ipairs(type(response.content) == "table" and response.content or {}) do
        if type(block) == "table" and block.type == "text" then
          local decoded, reading = pcall(vim.json.decode, block.text or "")
          if decoded and type(reading) == "table" then
            return callback(reading)
          end
        end
      end
      callback(nil, "Claude's answer wasn't the drawing asked for")
    end)
  end)
end

--- Read a pull request. `callback(reading, problem, from_cache)`.
---@param opts? { fresh?: boolean }
function M.read(pr, diff, opts, callback)
  opts = opts or {}
  local path = cache_path(pr)
  if not opts.fresh then
    local file = io.open(path, "r")
    if file then
      local ok, saved = pcall(vim.json.decode, file:read("*a"))
      file:close()
      if ok and type(saved) == "table" and saved.version == VERSION then
        local reading = M.validate(saved.reading, diff)
        if reading then
          return callback(reading, nil, true)
        end
      end
    end
  end
  local engine = M.engine()
  if not engine then
    return callback(nil, "no-engine")
  end
  local prompt = M.prompt(pr, diff)
  local started = vim.uv.now()
  local run = engine == "cli" and run_cli or run_api
  local ok, handle = pcall(run, prompt, function(answer, problem)
    if not answer then
      return callback(nil, problem)
    end
    local raw = vim.deepcopy(answer)
    local reading, invalid = M.validate(answer, diff)
    if not reading then
      return callback(nil, invalid)
    end
    reading.seconds = (vim.uv.now() - started) / 1000
    local file = io.open(path, "w")
    if file then
      file:write(vim.json.encode({ version = VERSION, reading = raw }))
      file:close()
    end
    callback(reading, nil, false)
  end)
  if not ok then
    callback(nil, tostring(handle))
    return nil
  end
  return handle
end

return M
