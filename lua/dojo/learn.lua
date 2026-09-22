-- Learning helpers, all one toggle away. The built-in :Tutor name belongs to
-- the AI Tutor here, so Vim's own interactive lesson lives at :VimTutor.

local M = {}

local function notify(message)
  vim.notify(message, vim.log.levels.INFO, { title = "Dojo" })
end

function M.vim_tutor(lesson)
  vim.fn["tutor#TutorCmd"](lesson or "vim-01-beginner")
end

function M.toggle_hints()
  local ok, precognition = pcall(require, "precognition")
  if not ok then
    notify("Motion hints need precognition.nvim")
    return
  end
  local visible = precognition.toggle()
  notify(visible and "Motion hints on — the letters show where w b e ^ $ would jump" or "Motion hints off")
end

function M.toggle_showkeys()
  if vim.fn.exists(":Screenkey") == 2 then
    vim.cmd("Screenkey toggle")
  else
    notify("On-screen keys need screenkey.nvim")
  end
end

function M.toggle_hardtime()
  if vim.fn.exists(":Hardtime") == 2 then
    vim.cmd("Hardtime toggle")
  end
end

function M.hardtime_report()
  if vim.fn.exists(":Hardtime") == 2 then
    vim.cmd("Hardtime report")
  end
end

function M.toggle_vfx()
  require("dojo.gui").toggle_vfx()
end

function M.menu()
  local items = {
    {
      "Vim tutor — lesson 1 (30 min, interactive)",
      function()
        M.vim_tutor("vim-01-beginner")
      end,
    },
    {
      "Vim tutor — lesson 2",
      function()
        M.vim_tutor("vim-02-beginner")
      end,
    },
    {
      "Motions game (vim-be-good)",
      function()
        vim.cmd("VimBeGood")
      end,
    },
    {
      "Typing practice (typr)",
      function()
        vim.cmd("Typr")
      end,
    },
    { "Your habits report (hardtime)", M.hardtime_report },
    { "Toggle motion hints", M.toggle_hints },
    { "Toggle on-screen keys", M.toggle_showkeys },
    {
      "Keyboard shortcuts",
      function()
        require("dojo.cheatsheet").open()
      end,
    },
  }
  vim.ui.select(items, {
    prompt = "Learn & Practise",
    format_item = function(item)
      return item[1]
    end,
  }, function(choice)
    if choice then
      choice[2]()
    end
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("VimTutor", function(opts)
    M.vim_tutor(opts.args ~= "" and opts.args or nil)
  end, {
    nargs = "?",
    desc = "Vim's built-in interactive tutor",
    complete = function()
      return { "vim-01-beginner", "vim-02-beginner" }
    end,
  })
  vim.api.nvim_create_user_command("DojoLearn", M.menu, { desc = "Learn & practise Vim" })
end

return M
