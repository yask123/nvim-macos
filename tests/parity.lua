-- The Mac-editor layer and the pull request review: selections you can type
-- over, chords that do nothing when nothing is bound, plain-language errors,
-- quitting without questions, the `code` command's requests, language setup,
-- and the review's parser, reading, drawing and sending.

local function equal(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
  )
end

-- Run whatever keys are waiting, as a person's typing would be.
local function flush()
  vim.api.nvim_feedkeys("", "x", false)
end

local function keys(text)
  vim.api.nvim_feedkeys(vim.keycode(text), "mx", false)
end

local function page(lines, cursor)
  vim.cmd("enew!")
  vim.bo.buftype = "nofile"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, cursor or { 1, 0 })
end

local function selected()
  local mode = vim.fn.mode()
  local kind = ({ s = "v", S = "V" })[mode] or mode
  return table.concat(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = kind }), "\n")
end

local function text()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function run()
  -- No resizing here: without a UI, changing 'columns' corrupts Neovim 0.12's
  -- memory (see tests/dojo.lua).
  vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
  vim.wait(200)
  -- which-key polls the keymap table from a timer, which headless Neovim 0.12
  -- can crash on (see tests/dojo.lua); it isn't what is tested here.
  pcall(vim.api.nvim_del_augroup_by_name, "wk")
  pcall(function()
    require("which-key.buf").get = function() end
  end)
  pcall(function()
    require("which-key.triggers").attach = function() end
  end)

  ---------------------------------------------------------------------------
  -- Keys every Mac editor has.
  for lhs, desc in pairs({
    ["<D-n>"] = "New file",
    ["<D-t>"] = "Terminal: show / hide the bottom panel",
    ["<D-j>"] = "Terminal: show / hide the bottom panel",
    ["<D-S-s>"] = "Save as…",
    ["<D-l>"] = "Select line (again: the next one too)",
    ["<D-a>"] = "Select all",
    ["<D-d>"] = "Select word, then its next occurrence",
    ["<C-Tab>"] = "Next / previous open file (⌘⇧] ⌘⇧[ too)",
    ["<D-k><D-p>"] = "Review a pull request",
  }) do
    equal(vim.fn.maparg(lhs, "n", false, true).desc, desc, "mapping " .. lhs)
  end
  -- A ⌘ chord nothing is bound to does nothing, in every mode: Neovim would
  -- otherwise run the bare key (⌘U would undo) or type "<D-u>" into the file.
  local unbound = require("dojo.mac").unbound_chord
  for _, lhs in ipairs({ "<D-u>", "<D-i>", "<D-S-y>", "<D-M-u>", "<C-D-u>" }) do
    local key = vim.keycode(lhs)
    assert(unbound(key, key), lhs .. " is dropped when nothing is bound to it")
  end
  assert(not unbound("u", vim.keycode("<D-u>")), "a chord a mapping answered is left alone")
  assert(not unbound("u", "u"), "ordinary keys pass")
  assert(not unbound(vim.keycode("<Left>"), vim.keycode("<Left>")), "arrow keys pass")
  assert(not unbound(vim.keycode("<D-LeftMouse>"), vim.keycode("<D-LeftMouse>")), "⌘-click passes")
  -- Ctrl-W stays Vim's window prefix.
  assert(vim.fn.maparg("<C-w>", "n", false, true).desc ~= "Close buffer", "Ctrl-W is left to Vim")
  -- Nothing printable is mapped in Select mode, or typing over a selection breaks.
  for _, map in ipairs(vim.api.nvim_get_keymap("s")) do
    assert(
      map.lhs:match("^<") and not map.lhs:match("^<Space>"),
      "a printable key is mapped in Select mode: " .. map.lhs
    )
  end

  ---------------------------------------------------------------------------
  -- Selecting the Mac way: from one caret to another, typed over.
  local mac = require("dojo.mac")
  page({ "abcdef", "second line" }, { 1, 2 })
  mac.extend("right")
  equal(vim.fn.mode(), "s", "Shift+→ starts a Select-mode selection")
  equal(selected(), "c", "Shift+→ selects exactly one character")
  mac.extend("right")
  flush()
  equal(selected(), "cd", "a second Shift+→ adds one")
  keys("X")
  equal(text()[1], "abXef", "typing replaces the selection")
  vim.cmd.stopinsert()
  flush()

  -- Back across where it started: the selection shrinks to nothing, then grows the other way.
  page({ "abcdef" }, { 1, 3 })
  mac.extend("left")
  equal(selected(), "c", "Shift+← selects the character before the caret")
  mac.extend("left")
  flush()
  equal(selected(), "bc", "and the one before it")
  mac.extend("right")
  flush()
  mac.extend("right")
  flush()
  equal(vim.fn.mode(), "n", "back at the start, nothing is selected")
  mac.extend("right")
  equal(selected(), "d", "and on the other side it grows again")
  mac.collapse("left")
  flush()
  equal({ vim.fn.mode(), vim.api.nvim_win_get_cursor(0)[2] }, { "n", 3 }, "← lets go at the selection's start")

  -- Whole lines with Shift+↓, deleted with Backspace.
  page({ "one", "two", "three" }, { 1, 0 })
  mac.extend("down")
  mac.extend("down")
  flush()
  equal(selected(), "one\ntwo", "Shift+↓ twice selects two lines")
  mac.delete()
  flush()
  equal(text(), { "three" }, "Backspace deletes them, line breaks included")

  -- By word, to the line's end, and everything.
  page({ "hello world foo" }, { 1, 0 })
  mac.extend("word_right")
  equal(selected(), "hello", "⌥⇧→ selects a word")
  mac.extend("line_end")
  flush()
  equal(selected(), "hello world foo", "⌘⇧→ selects to the end of the line")
  vim.cmd("normal! \27")
  page({ "one", "two" }, { 2, 1 })
  mac.select_all()
  equal({ vim.fn.mode(), selected() }, { "s", "one\ntwo" }, "⌘A selects everything, ready to type over")
  mac.copy()
  equal(vim.fn.getreg("+"), "one\ntwo", "⌘C copies and keeps the selection")
  equal(vim.fn.mode(), "s", "still selected after copying")
  vim.cmd("normal! \27")
  -- A file tree or a list is not text to type over.
  vim.bo.modifiable = false
  mac.extend("right")
  equal(vim.fn.mode(), "n", "no Mac selection in a read-only view")
  vim.bo.modifiable = true

  -- ⌘D: the word, then its next occurrence; typing changes every copy.
  local actions = require("dojo.actions")
  page({ "alpha beta", "foo alpha", "alpha end" }, { 1, 1 })
  actions.add_next_occurrence()
  equal({ vim.fn.mode(), selected() }, { "s", "alpha" }, "⌘D selects the word")
  actions.add_next_occurrence()
  actions.add_next_occurrence()
  equal(require("multicursor-nvim").numCursors(), 3, "two more presses, three selections")
  equal(vim.fn.mode(), "s", "all of them ready to type over")
  require("multicursor-nvim").clearCursors()
  vim.cmd("normal! \27")

  ---------------------------------------------------------------------------
  -- Errors in plain words.
  local calm = require("dojo.calm")
  equal(calm.soften("E486: Pattern not found: zzz"), "No matches for “zzz”", "search miss")
  equal(
    calm.soften("E492: Not an editor command: foo"),
    "No command called “foo”. ⌘⇧P lists them all.",
    "unknown command"
  )
  equal(
    calm.soften("E37: No write since last change (add ! to override)"),
    "Unsaved changes here. ⌘S saves them.",
    "unsaved"
  )
  equal(calm.soften("E21: Cannot make changes, 'modifiable' is off"), "This view can't be edited", "read-only view")
  assert(
    calm
      .soften("E5108: Lua: foo.lua:3: attempt to index a nil value\nstack traceback:\n\t[C]: in function")
      :find("Something went wrong inside Code", 1, true),
    "a stack trace never reaches the screen"
  )
  equal(calm.soften("E325: ATTENTION"), nil, "swap-file chatter is dropped")
  equal(calm.soften("WARNING: The file has been changed since reading it!!!"), nil, "disk-change prompt is dropped")
  equal(calm.soften("E999: Something odd (add ! to override)"), "Something odd", "any other code is stripped")
  equal(calm.soften("Saved the planet"), "Saved the planet", "ordinary messages pass through")
  local notif = { msg = "E486: Pattern not found: q", level = "error", icon = "x" }
  assert(calm.filter(notif), "a softened message is still shown")
  equal({ notif.msg, notif.level }, { "No matches for “q”", "info" }, "…as information, not an error")
  assert(not calm.filter({ msg = "E486: Pattern not found: q", level = "error", icon = "x" }), "and only once")
  assert(#calm.log >= 1, "the original is kept for Show Log")

  ---------------------------------------------------------------------------
  -- Quitting never asks: untitled pages are put away and come back.
  local exit = require("dojo.exit")
  local temp = vim.fs.dirname(vim.fn.tempname())
  vim.fn.mkdir(temp, "p")
  local folder = vim.uv.fs_realpath(temp) .. "/parity-" .. vim.uv.hrtime()
  vim.fn.mkdir(folder, "p")
  vim.fn.chdir(folder)
  vim.cmd("enew!")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a thought", "not saved anywhere" })
  local untitled = vim.api.nvim_get_current_buf()
  equal(exit.stash(), 1, "one untitled page put away")
  equal(vim.bo[untitled].modified, false, "nothing left for Vim to ask about")
  vim.cmd("bwipeout! " .. untitled)
  equal(exit.restore(), 1, "and brought back")
  local back
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "a thought" then
      back = buf
    end
  end
  assert(back and vim.bo[back].modified, "the page is back, still marked unsaved")
  equal(exit.restore(), 0, "once only")
  vim.cmd("bwipeout! " .. back)

  ---------------------------------------------------------------------------
  -- Files changed on disk: with unsaved edits here, yours are kept and the
  -- disk's version waits for Revert File. (The reload itself happens in
  -- Neovim's main loop, which a script never returns to; it is driven with a
  -- real session in the QA recipe.)
  local disk_file = folder .. "/watched.txt"
  vim.fn.writefile({ "one" }, disk_file)
  vim.cmd.edit(vim.fn.fnameescape(disk_file))
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "mine" })
  vim.fn.writefile({ "theirs" }, disk_file)
  vim.api.nvim_exec_autocmds("FileChangedShell", { buffer = 0 })
  equal(vim.b.dojo_changed_on_disk, true, "with unsaved edits, the disk's version waits")
  equal(text()[1], "mine", "and your edits stay")
  require("dojo.disk").revert()
  equal(text(), { "theirs" }, "Revert File takes the disk's version")
  equal(vim.b.dojo_changed_on_disk, nil, "and the file is in step with the disk again")
  vim.cmd("bwipeout!")

  ---------------------------------------------------------------------------
  -- The `code` command's requests.
  local cli = require("dojo.cli")
  local target = folder .. "/notes.txt"
  vim.fn.writefile({ "one", "two", "three", "four" }, target)
  local request = vim.fn.tempname()
  vim.fn.writefile({ "file\t" .. target .. "\t3\t2", "wait\ttoken-1" }, request)
  cli.run(request)
  equal(vim.api.nvim_buf_get_name(0), target, "code file:3:2 opens the file")
  equal(vim.api.nvim_win_get_cursor(0), { 3, 1 }, "at line 3, column 2")
  equal(cli.waiting("token-1"), 1, "code --wait waits while the file is open")
  vim.cmd("bdelete!")
  equal(cli.waiting("token-1"), 0, "and stops when it is closed")
  assert(not vim.uv.fs_stat(request), "the request file is cleaned up")
  local piped = vim.fn.tempname()
  vim.fn.writefile({ "from a pipe" }, piped)
  vim.fn.writefile({ "stdin\t" .. piped }, request)
  cli.run(request)
  equal({ text()[1], vim.bo.modified }, { "from a pipe", true }, "piped text becomes an untitled page")
  vim.cmd("bwipeout!")

  ---------------------------------------------------------------------------
  -- Languages: every server named has a configuration to start from, and ⌘R
  -- knows a Rails test from a script.
  local lang = require("dojo.lang")
  local filetypes = {}
  for _, entry in ipairs(lang.languages) do
    assert(vim.lsp.config[entry.server], "no language server configuration for " .. entry.server)
    for _, filetype in ipairs(entry.filetypes) do
      assert(not filetypes[filetype], filetype .. " is claimed twice")
      filetypes[filetype] = true
    end
  end
  local runner = require("config.runner")
  local rails = folder .. "/shop"
  vim.fn.mkdir(rails .. "/bin", "p")
  vim.fn.mkdir(rails .. "/config", "p")
  vim.fn.mkdir(rails .. "/test/models", "p")
  vim.fn.writefile({ "" }, rails .. "/Gemfile")
  vim.fn.writefile({ "" }, rails .. "/bin/rails")
  vim.fn.writefile({ "" }, rails .. "/config/application.rb")
  equal(
    (runner.command_for(rails .. "/test/models/cart_test.rb", "ruby")),
    { "bin/rails", "test", "test/models/cart_test.rb" },
    "a Rails test runs as a test"
  )
  equal(
    (runner.command_for(rails .. "/spec/cart_spec.rb", "ruby")),
    { "bundle", "exec", "rspec", "spec/cart_spec.rb" },
    "a spec runs with rspec"
  )
  equal(
    (runner.command_for(folder .. "/hello.rb", "ruby")),
    { "ruby", folder .. "/hello.rb" },
    "a plain script runs with ruby"
  )
  local _, _, why = runner.command_for(folder .. "/x.kt", "kotlin")
  assert(why and why:find("doesn't know how to run", 1, true), "an unknown language says so plainly")

  ---------------------------------------------------------------------------
  -- Review: the diff, parsed.
  local patch = table.concat({
    "diff --git a/src/cache.ts b/src/cache.ts",
    "new file mode 100644",
    "index 0000000..1111111",
    "--- /dev/null",
    "+++ b/src/cache.ts",
    "@@ -0,0 +1,3 @@",
    "+export class Cache {",
    "+  get(id: string) {}",
    "+}",
    "diff --git a/src/reader.ts b/src/reader.ts",
    "index 2222222..3333333 100644",
    "--- a/src/reader.ts",
    "+++ b/src/reader.ts",
    "@@ -10,4 +10,5 @@ export class Reader {",
    "   read(id: string) {",
    "-    return this.service.get(id);",
    "+    const hit = this.cache.get(id);",
    "+    return hit ?? this.service.get(id);",
    "   }",
    " }",
    "@@ -40,2 +41,3 @@ function helper() {",
    "   one();",
    "+  two();",
    "   three();",
    "diff --git a/package-lock.json b/package-lock.json",
    "index 4444444..5555555 100644",
    "--- a/package-lock.json",
    "+++ b/package-lock.json",
    "@@ -1,2 +1,3 @@",
    " {",
    '+  "redis": "5.0.0",',
    " }",
    "",
  }, "\n")
  local diff = require("dojo.review.diff").parse(patch)
  equal(#diff.files, 3, "three files")
  equal({ diff.additions, diff.deletions }, { 7, 1 }, "lines added and removed")
  equal({ diff.files[1].status, diff.files[1].path }, { "added", "src/cache.ts" }, "a new file")
  equal(#diff.files[2].hunks, 2, "two hunks in the second file")
  local hunk = diff.hunks.f2h1
  equal({ hunk.context, hunk.old_start, hunk.new_start }, { "export class Reader {", 10, 10 }, "hunk header")
  equal(
    vim.tbl_map(function(line)
      return { line.kind, line.old or false, line.new or false }
    end, hunk.lines),
    { { " ", 10, 10 }, { "-", 11, false }, { "+", false, 11 }, { "+", false, 12 }, { " ", 12, 13 }, { " ", 13, 14 } },
    "every line knows its number on each side"
  )
  assert(diff.files[3].mechanical, "a lockfile is mechanical")
  local shown = require("dojo.review.diff").prompt(diff)
  assert(
    shown:find("### f2h2", 1, true) and shown:find("(mechanical: not shown)", 1, true),
    "the reading sees labelled hunks, not lockfiles"
  )

  -- The reading, checked before anything is drawn from it.
  local reading_module = require("dojo.review.reading")
  local answer = {
    headline = "Cache reads",
    kind = "performance",
    was = "slow",
    now = "fast",
    how = "a cache",
    cast = {
      { id = "you", name = "You", kind = "person", role = "", change = "unchanged" },
      { id = "reader", name = "Reader", kind = "service", role = "", change = "changed" },
      { id = "cache", name = "Cache", kind = "store", role = "", change = "added" },
      { id = "service", name = "Service", kind = "service", role = "", change = "unchanged" },
      { id = "you", name = "Twice", kind = "person", role = "", change = "unchanged" },
    },
    flow = {
      { from = "you", to = "reader", does = "read", data = "id", status = "same", was = "", hunk = "" },
      { from = "reader", to = "cache", does = "look up", data = "id", status = "added", was = "", hunk = "f2h1" },
      { from = "reader", to = "service", does = "get", data = "", status = "changed", was = "always", hunk = "f9h9" },
      { from = "reader", to = "nowhere", does = "lost", data = "", status = "same", was = "", hunk = "" },
    },
    breaks = 2,
    pain = "every read hit the database",
    chapters = {
      { title = "Read path", attention = "focus", hunks = { "f2h1", "f1h1", "f2h1", "f7h1" } },
    },
    notes = { { hunk = "f2h1", note = "Asks the cache first" }, { hunk = "f7h1", note = "nope" } },
  }
  local reading = assert(reading_module.validate(vim.deepcopy(answer), diff))
  equal(#reading.cast, 4, "a part named twice counts once")
  equal(#reading.flow, 3, "a step to a part that doesn't exist is dropped")
  equal(reading.flow[3].hunk, nil, "a hunk that doesn't exist is forgotten")
  equal(reading.chapters[1].hunks, { "f2h1", "f1h1" }, "each real hunk once")
  equal(reading.chapters[2].hunks, { "f2h2", "f3h1" }, "hunks the reading left out still get read")
  equal(reading.notes, { f2h1 = "Asks the cache first" }, "notes by hunk")
  equal(reading_module.validate({ cast = {}, flow = {} }, diff), nil, "nothing to draw is not a reading")
  local plain = reading_module.plain(diff)
  equal(plain.chapters[2].hunks, { "f3h1" }, "without Claude, mechanical files go last")
  assert(
    reading_module
      .prompt({ owner = "o", repo = "r", number = 7, title = "T", body = "why" }, diff)
      :find("o/r #7: T", 1, true),
    "the prompt names the PR"
  )

  -- The trace: one line, a dot per step, coloured by what changed.
  local trace = require("dojo.review.trace")
  equal(trace.visible(reading, "before"), { 1, 3 }, "before: no added steps")
  equal(trace.visible(reading, "after"), { 1, 2, 3 }, "after: every step that still happens")
  local drawn = trace.draw(reading, { width = 120, telling = "diff", focus = 2 })
  equal(#drawn.lines, #reading.cast * 3 + 1, "three rows a rail, and the step numbers")
  local picture = table.concat(
    vim.tbl_map(function(line)
      return line.text
    end, drawn.lines),
    "\n"
  )
  for _, name in ipairs({ "You", "Reader", "Cache", "Service", "look up", "◉", "✕", "01", "03" }) do
    assert(picture:find(name, 1, true), "the trace shows " .. name)
  end
  assert(drawn.steps[2] and drawn.steps[2].col > 0, "each step knows where its dot is")
  local groups = {}
  for _, line in ipairs(drawn.lines) do
    for _, mark in ipairs(line.marks) do
      groups[mark[3]] = true
    end
  end
  assert(
    groups.DojoReviewAdded and groups.DojoReviewChanged and groups.DojoReviewFocus,
    "added, changed and focus each have a colour"
  )
  equal(
    #trace.draw(reading, { width = 120, telling = "after", reveal = 1 }).steps,
    1,
    "the line can draw itself a step at a time"
  )

  -- The page and the code view.
  local state = {
    pr = {
      number = 7,
      owner = "o",
      repo = "r",
      title = "Cache reads",
      author = { login = "ana" },
      headRefName = "cache",
      baseRefName = "main",
      headRefOid = "abc",
      url = "https://github.com/o/r/pull/7",
    },
    diff = diff,
    reading = reading,
    reading_state = "ready",
    telling = "diff",
    focus = 2,
    pending = { { path = "src/reader.ts", line = 11, side = "RIGHT", body = "why not await?" } },
    threads = { { path = "src/reader.ts", line = 12, side = "RIGHT", comments = { { author = "bo", body = "nice" } } } },
  }
  local built = require("dojo.review.page").build(state, 150)
  local page_text = table.concat(
    vim.tbl_map(function(line)
      return line.text
    end, built.lines),
    "\n"
  )
  for _, expected in ipairs({
    "#7",
    "o/r",
    "Cache reads",
    "Before",
    "Trace",
    "Read, in this order",
    "src/",
    "reader.ts",
    "Asks the cache first",
    "package-lock.json",
  }) do
    assert(page_text:find(expected, 1, true), "the page shows " .. expected)
  end
  local opens = 0
  for _, target in pairs(built.targets) do
    assert(diff.hunks[target.hunk], "every ↩ leads to a real hunk")
    opens = opens + 1
  end
  assert(opens >= 4, "the step and the files can be opened")
  assert(built.trace_top and built.steps[2], "the page knows where the trace is")
  state.reading, state.reading_state = nil, "none"
  local bare = table.concat(
    vim.tbl_map(function(line)
      return line.text
    end, require("dojo.review.page").build(state, 150).lines),
    "\n"
  )
  assert(
    bare:find("Files", 1, true) and bare:find("ANTHROPIC_API_KEY", 1, true),
    "without Claude the files are still there"
  )
  state.reading = reading

  local code = require("dojo.review.code")
  local buf = code.buffer(state, diff.files[2])
  equal(
    vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1],
    "    return this.service.get(id);",
    "removed lines are shown too"
  )
  equal(
    code.at(state, buf, 2),
    { path = "src/reader.ts", side = "LEFT", line = 11, hunk = "f2h1", kind = "-" },
    "a removed line comments on the old side"
  )
  equal(code.at(state, buf, 3).line, 11, "an added line on the new side")
  equal(code.line_of(buf, "f2h2"), 7, "a hunk knows its first line")
  equal(code.next_change(buf, 1, 1), 2, "] goes to the next change")
  equal(code.next_change(buf, 2, 1), 8, "and past the one it is in")
  equal(code.next_change(buf, 8, -1), 2, "[ goes back")
  assert(
    code.gutter_for(buf, 3):find("11", 1, true) and code.gutter_for(buf, 3):find("+", 1, true),
    "the gutter shows the line number and a +"
  )
  assert(code.gutter_for(buf, 2):find("−", 1, true), "and a − for a removed line")
  local notes =
    vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("dojo_review_notes"), 0, -1, { details = true })
  equal(#notes, 2, "the waiting comment and GitHub's thread sit under their lines")
  vim.cmd("enew!")

  -- Sending a review: exactly what was written, to the right pull request.
  local bin = folder .. "/bin"
  vim.fn.mkdir(bin, "p")
  local record = folder .. "/gh-call.txt"
  vim.fn.writefile({
    "#!/bin/sh",
    'printf "%s\\n" "$*" > "' .. record .. '"',
    'cat >> "' .. record .. '"',
    "echo '{}'",
  }, bin .. "/gh")
  vim.fn.setfperm(bin .. "/gh", "rwxr-xr-x")
  local old_path = vim.env.PATH
  vim.env.PATH = bin .. ":" .. old_path
  local sent
  require("dojo.review.github").submit(state.pr, "APPROVE", "Reads well.", state.pending, function(ok)
    sent = ok
  end)
  vim.wait(5000, function()
    return sent ~= nil
  end, 50)
  vim.env.PATH = old_path
  equal(sent, true, "the review goes out")
  local call = vim.fn.readfile(record)
  equal(call[1], "api --method POST repos/o/r/pulls/7/reviews --input -", "to this pull request's reviews")
  local payload = vim.json.decode(table.concat(vim.list_slice(call, 2), "\n"))
  equal(payload.event, "APPROVE", "as an approval")
  equal(payload.body, "Reads well.", "with the sentence written")
  equal(payload.commit_id, "abc", "for the commit that was read")
  equal(
    payload.comments,
    { { path = "src/reader.ts", line = 11, side = "RIGHT", body = "why not await?" } },
    "and the line comments"
  )
  equal(
    require("dojo.review.github").explain("no pull requests found"),
    "GitHub has no such pull request (or you can't see it).",
    "GitHub's errors in plain words"
  )

  vim.fn.delete(folder, "rf")
  io.stdout:write("Parity test passed (selection, errors, quitting, code command, languages, review)\n")
  io.stdout:flush()
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  os.exit(1)
end
-- See tests/dojo.lua: quitting through Neovim's own teardown can crash here.
os.exit(0)
