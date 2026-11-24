-- GitHub, through the `gh` command the user is already signed in to.

local M = {}

local function gh(args, opts, callback)
  opts = opts or {}
  local cmd = { "gh" }
  vim.list_extend(cmd, args)
  local ok, err = pcall(
    vim.system,
    cmd,
    { text = true, cwd = opts.cwd, stdin = opts.stdin, timeout = opts.timeout or 30000 },
    function(result)
      vim.schedule(function()
        if result.code == 0 then
          callback(result.stdout or "", nil)
        else
          callback(
            nil,
            vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or ("gh exited with " .. result.code)
          )
        end
      end)
    end
  )
  if not ok then
    vim.schedule(function()
      callback(nil, tostring(err))
    end)
  end
end

--- Why GitHub can't be reached, in plain words (nil when it can).
function M.problem()
  if vim.fn.executable("gh") ~= 1 then
    return "Reviewing pull requests uses GitHub's `gh` command. Install it with: brew install gh"
  end
  return nil
end

function M.explain(err)
  err = err or ""
  if err:find("gh auth login") or err:find("not logged in") or err:find("authentication") then
    return "Sign in to GitHub first: run `gh auth login` in the terminal (⌘T)."
  elseif err:find("not a git repository") or err:find("no git remotes") or err:find("none of the git remotes") then
    return "This folder isn't a GitHub repository. Paste a pull request link instead."
  elseif err:find("Could not resolve") or err:find("no pull requests found") or err:find("not found") then
    return "GitHub has no such pull request (or you can't see it)."
  elseif err:find("dial tcp") or err:find("no such host") or err:find("timeout") then
    return "Can't reach GitHub. Are you offline?"
  end
  return (err:match("^[^\n]*") or err)
end

local list_fields =
  "number,title,author,headRefName,baseRefName,additions,deletions,changedFiles,isDraft,reviewDecision,updatedAt,url"

--- Open pull requests of the repository in `cwd`.
function M.list(cwd, callback)
  gh({ "pr", "list", "--limit", "50", "--json", list_fields }, { cwd = cwd }, function(out, err)
    if not out then
      return callback(nil, err)
    end
    local ok, prs = pcall(vim.json.decode, out)
    callback(ok and prs or {}, nil)
  end)
end

--- Pull requests anywhere that wait for the user's review.
function M.waiting(callback)
  gh({
    "search",
    "prs",
    "--review-requested=@me",
    "--state=open",
    "--limit",
    "30",
    "--json",
    "number,title,author,repository,updatedAt,url",
  }, {}, function(out)
    local ok, prs = pcall(vim.json.decode, out or "[]")
    callback(ok and prs or {})
  end)
end

local view_fields = "number,title,author,headRefName,baseRefName,headRefOid,additions,deletions,changedFiles,state,isDraft,"
  .. "reviewDecision,url,body,statusCheckRollup,mergeable"

--- One pull request: its facts and its diff. `ref` is a number or a link.
function M.fetch(ref, cwd, callback)
  local pr, diff, failed
  local function done()
    if failed then
      return
    end
    if pr and diff then
      callback({ pr = pr, diff = diff }, nil)
    end
  end
  local function fail(err)
    if not failed then
      failed = true
      callback(nil, err)
    end
  end
  gh({ "pr", "view", tostring(ref), "--json", view_fields }, { cwd = cwd }, function(out, err)
    if not out then
      return fail(err)
    end
    local ok, data = pcall(vim.json.decode, out)
    if not ok then
      return fail("GitHub answered with something unreadable")
    end
    data.owner, data.repo = (data.url or ""):match("github%.com/([^/]+)/([^/]+)/pull/")
    pr = data
    done()
  end)
  gh({ "pr", "diff", tostring(ref), "--color", "never" }, { cwd = cwd, timeout = 60000 }, function(out, err)
    if not out then
      return fail(err)
    end
    diff = out
    done()
  end)
end

local threads_query = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          isResolved isOutdated path line originalLine diffSide
          comments(first: 30) { nodes { author { login } body createdAt } }
        }
      }
    }
  }
}]]

--- Review comments already on the pull request, by thread.
function M.threads(pr, callback)
  if not pr.owner then
    return callback({})
  end
  gh({
    "api",
    "graphql",
    "-f",
    "query=" .. threads_query,
    "-f",
    "owner=" .. pr.owner,
    "-f",
    "repo=" .. pr.repo,
    "-F",
    "number=" .. pr.number,
  }, {}, function(out)
    local ok, data = pcall(vim.json.decode, out or "")
    local nodes = ok and vim.tbl_get(data, "data", "repository", "pullRequest", "reviewThreads", "nodes") or {}
    local threads = {}
    for _, node in ipairs(type(nodes) == "table" and nodes or {}) do
      local comments = {}
      for _, comment in ipairs(vim.tbl_get(node, "comments", "nodes") or {}) do
        comments[#comments + 1] =
          { author = vim.tbl_get(comment, "author", "login") or "someone", body = comment.body or "" }
      end
      local line = type(node.line) == "number" and node.line
        or (type(node.originalLine) == "number" and node.originalLine or nil)
      if #comments > 0 and line then
        threads[#threads + 1] = {
          path = node.path,
          line = line,
          side = node.diffSide == "LEFT" and "LEFT" or "RIGHT",
          resolved = node.isResolved == true,
          outdated = node.isOutdated == true,
          comments = comments,
        }
      end
    end
    callback(threads)
  end)
end

--- Who `gh` is signed in as.
function M.login(callback)
  gh({ "api", "user", "--jq", ".login" }, {}, function(out)
    callback(out and vim.trim(out) or nil)
  end)
end

--- Send a review. `event` is APPROVE, REQUEST_CHANGES or COMMENT.
---@param comments {path: string, line: integer, side: string, body: string}[]
function M.submit(pr, event, body, comments, callback)
  local payload = { event = event, commit_id = pr.headRefOid, comments = {} }
  if body and vim.trim(body) ~= "" then
    payload.body = body
  end
  for _, comment in ipairs(comments or {}) do
    payload.comments[#payload.comments + 1] =
      { path = comment.path, line = comment.line, side = comment.side, body = comment.body }
  end
  if #payload.comments == 0 then
    payload.comments = nil
  end
  gh({
    "api",
    "--method",
    "POST",
    ("repos/%s/%s/pulls/%d/reviews"):format(pr.owner, pr.repo, pr.number),
    "--input",
    "-",
  }, { stdin = vim.json.encode(payload) }, function(out, err)
    callback(out ~= nil, err)
  end)
end

return M
