local function assert_equal(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
  )
end

local tutor = require("config.tutor")
tutor.setup()
require("config.keymaps")

local source = vim.api.nvim_create_buf(false, false)
vim.api.nvim_set_current_buf(source)
vim.api.nvim_buf_set_name(source, "/tmp/tutor selection.py")
vim.bo[source].filetype = "python"
vim.api.nvim_buf_set_lines(source, 0, -1, false, {
  "alpha βeta",
  "second line",
  "third",
})
vim.bo[source].modified = false

local charwise = tutor._context_from_region(source, { 0, 1, 7, 0 }, { 0, 1, 10, 0 }, "v")
assert_equal(charwise.text, "βet", "character-wise Unicode selection")
assert_equal(charwise.first_line, 1, "character-wise start line")
assert_equal(charwise.last_line, 1, "character-wise end line")

local reversed = tutor._context_from_region(source, { 0, 2, 3, 0 }, { 0, 1, 1, 0 }, "v")
assert(reversed.text:find("alpha", 1, true), "reversed selection should include its first endpoint")
assert_equal(reversed.first_line, 1, "reversed selection normalized start")
assert_equal(reversed.last_line, 2, "reversed selection normalized end")

local linewise = tutor._context_from_region(source, { 0, 1, 1, 0 }, { 0, 2, 1, 0 }, "V")
assert_equal(linewise.text, "alpha βeta\nsecond line", "line-wise selection")

local blockwise = tutor._context_from_region(source, { 0, 1, 1, 0 }, { 0, 2, 3, 0 }, string.char(22))
assert_equal(blockwise.text, "alp\nsec", "block-wise selection")

local bounded, limit_error = tutor._limit_context(string.rep("é", tutor._constants.max_context_chars + 1))
assert_equal(bounded, nil, "oversized context rejected")
assert(limit_error:find("too large", 1, true), "oversized context explains the next action")

local history = {}
for index = 1, 14 do
  table.insert(history, {
    role = index % 2 == 1 and "user" or "assistant",
    content = "message " .. index,
  })
end
local payload = tutor._build_payload(linewise, history, "test-model")
assert_equal(payload.model, "test-model", "explicit Tutor model")
assert_equal(payload.store, false, "server-side response storage disabled")
assert_equal(payload.tools, {}, "Tutor exposes no model tools")
assert_equal(payload.text.verbosity, "low", "low API verbosity")
assert_equal(payload.reasoning.context, "current_turn", "stateless reasoning context")
assert_equal(payload.input[2].role, "user", "trimmed history starts with a learner turn")
assert_equal(payload.input[#payload.input].content, "message 14", "trimmed history keeps the latest turn")

local answer, response_error = tutor._parse_response(vim.json.encode({
  output = {
    { type = "reasoning", summary = {} },
    { type = "message", content = { { type = "output_text", text = "First point." } } },
    { type = "message", content = { { type = "output_text", text = "Second point." } } },
  },
}))
assert_equal(answer, "First point.\nSecond point.", "all response text is collected")
assert_equal(response_error, nil, "valid response has no error")

local nullable_answer, nullable_error = tutor._parse_response(vim.json.encode({
  error = vim.NIL,
  status = "completed",
  output = {
    { type = "message", content = { { type = "output_text", text = "Null is not an error." } } },
  },
}))
assert_equal(nullable_answer, "Null is not an error.", "JSON null error field is ignored")
assert_equal(nullable_error, nil, "JSON null error field does not fail parsing")

local no_answer, api_error = tutor._parse_response(vim.json.encode({ error = { message = "Bad key" } }))
assert_equal(no_answer, nil, "API error has no answer")
assert_equal(api_error, "Bad key", "API error message is surfaced")

local incomplete_answer, incomplete_error = tutor._parse_response(vim.json.encode({
  status = "incomplete",
  incomplete_details = { reason = "max_output_tokens" },
  output = { { type = "message", content = { { type = "output_text", text = "Cut off" } } } },
}))
assert_equal(incomplete_answer, nil, "incomplete response is not shown as complete")
assert(incomplete_error:find("narrower question", 1, true), "incomplete response gives a useful next action")

local old_key = vim.env.OPENAI_API_KEY
vim.env.OPENAI_API_KEY = "test-secret-that-must-not-appear"
local command = tutor._request_command()
assert_equal(command, { "python3", tutor._constants.helper_path }, "transport uses fixed arguments")
assert(not table.concat(command, " "):find(vim.env.OPENAI_API_KEY, 1, true), "transport argv does not expose the key")
vim.env.OPENAI_API_KEY = old_key

local source_lines = vim.api.nvim_buf_get_lines(source, 0, -1, false)
local source_tick = vim.api.nvim_buf_get_changedtick(source)
local source_win = vim.api.nvim_get_current_win()
local original_columns = vim.o.columns
local original_lines = vim.o.lines
vim.o.columns = 80
vim.o.lines = 40
tutor.toggle()

local panel
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_get_name(buf) == "tutor://chat" then
    panel = buf
    break
  end
end
assert(panel, "Tutor panel should exist")
assert_equal(vim.bo[panel].buftype, "nofile", "Tutor panel is a scratch buffer")
assert_equal(vim.bo[panel].buflisted, false, "Tutor panel is not listed")
assert_equal(vim.bo[panel].filetype, "tutor", "Tutor panel avoids Markdown UI plugins")
assert_equal(vim.bo[panel].syntax, "markdown", "Tutor transcript keeps readable syntax highlighting")
assert_equal(vim.bo[panel].modifiable, false, "Tutor transcript is read-only")
assert_equal(vim.bo[panel].swapfile, false, "Tutor transcript has no swap file")
assert(vim.fn.maparg("q", "n", false, true).buffer == 1, "Tutor panel has a local close key")
local narrow_panel_win = vim.fn.win_findbuf(panel)[1]
assert_equal(vim.api.nvim_win_get_width(narrow_panel_win), 80, "narrow Tutor uses a bottom panel")
assert(vim.api.nvim_win_get_height(narrow_panel_win) < 40, "narrow Tutor preserves source width")
assert_equal(vim.wo[narrow_panel_win].conceallevel, 0, "Tutor transcript does not conceal its controls")
assert_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), source_lines, "opening Tutor does not change source")
assert_equal(vim.api.nvim_buf_get_changedtick(source), source_tick, "opening Tutor preserves source changedtick")
tutor.toggle()

vim.o.columns = 160
tutor.toggle()
local wide_panel_win = vim.fn.win_findbuf(panel)[1]
local wide_panel_width = vim.api.nvim_win_get_width(wide_panel_win)
assert(wide_panel_width >= 38 and wide_panel_width <= 68, "wide Tutor uses a restrained right sidebar")
vim.api.nvim_set_current_win(source_win)
tutor.toggle()
assert_equal(vim.api.nvim_get_current_win(), wide_panel_win, "toggle focuses an open Tutor from the source")
tutor.toggle()
vim.o.columns = original_columns
vim.o.lines = original_lines

local saved_key = vim.env.OPENAI_API_KEY
vim.env.OPENAI_API_KEY = nil
tutor.submit("Why does this work?")
assert(tutor._state_for_test().notice:find("OPENAI_API_KEY", 1, true), "missing key has setup guidance")

local callbacks = {}
local kills = 0
tutor._set_transport_for_test(function(request_payload, callback)
  assert_equal(request_payload.store, false, "fake transport receives private request")
  table.insert(callbacks, callback)
  return {
    kill = function()
      kills = kills + 1
    end,
  }
end)
vim.env.OPENAI_API_KEY = "fake-key-for-test"

tutor.submit("First question")
assert_equal(tutor._state_for_test().waiting, true, "Tutor enters loading state")
tutor.stop()
assert_equal(kills, 1, "cancel stops the active transport")
callbacks[1]({
  code = 0,
  stdout = vim.json.encode({
    output = { { type = "message", content = { { type = "output_text", text = "Late answer" } } } },
  }),
  stderr = "",
})
vim.wait(20)
for _, message in ipairs(tutor._state_for_test().messages) do
  assert(message.content ~= "Late answer", "cancelled response must be ignored")
end

tutor.submit("Second question")
local second_context = tutor._context_from_buffer(source, 2, 2, "selection")
tutor._replace_context_for_test(second_context)
assert_equal(kills, 2, "changing context cancels the previous transport")
callbacks[2]({
  code = 0,
  stdout = vim.json.encode({
    output = { { type = "message", content = { { type = "output_text", text = "Wrong-context answer" } } } },
  }),
  stderr = "",
})
vim.wait(20)
local switched_state = tutor._state_for_test()
assert_equal(switched_state.context_label, second_context.label, "new context remains active")
assert_equal(switched_state.messages, {}, "old response cannot enter the new context")

tutor.submit("Third question")
callbacks[3]({
  code = 0,
  stdout = vim.json.encode({
    output = { { type = "message", content = { { type = "output_text", text = "Brief answer" } } } },
  }),
  stderr = "",
})
vim.wait(20, function()
  return not tutor._state_for_test().waiting
end)
local final_state = tutor._state_for_test()
assert_equal(final_state.messages[#final_state.messages].content, "Brief answer", "current response is rendered")

tutor._set_transport_for_test(nil)
vim.env.OPENAI_API_KEY = saved_key
assert_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), source_lines, "Tutor requests do not change source")
assert_equal(vim.api.nvim_buf_get_changedtick(source), source_tick, "Tutor requests preserve source changedtick")

assert(vim.fn.exists(":Tutor") == 2, "Tutor command is registered")
assert(vim.fn.maparg("<leader>ta", "n", false, true).desc == "Ask Tutor about file", "normal Tutor mapping")
assert(vim.fn.maparg("<leader>ta", "x", false, true).desc == "Ask Tutor about selection", "visual Tutor mapping")
assert(vim.fn.maparg("<leader>tt", "n", false, true).desc == "Toggle Tutor sidebar", "Tutor toggle mapping")

vim.api.nvim_buf_delete(source, { force = true })
print("Tutor test passed")
