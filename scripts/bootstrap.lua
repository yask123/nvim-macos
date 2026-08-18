local registry = require("mason-registry")
local tools = LazyVim.opts("mason.nvim").ensure_installed or {}
local wanted = {}

for _, name in ipairs(tools) do
  wanted[name] = true
end

local ok = registry.refresh()
if not ok then
  error("Mason registry refresh failed")
end

local failed = {}
registry:on("package:install:failed", function(package)
  failed[package.name] = true
end)

for name in pairs(wanted) do
  local package = registry.get_package(name)
  if not package:is_installed() and not package:is_installing() then
    package:install()
  end
end

local finished = vim.wait(300000, function()
  if next(failed) then
    return true
  end
  for name in pairs(wanted) do
    if not registry.get_package(name):is_installed() then
      return false
    end
  end
  return true
end, 250)

if not finished then
  error("Timed out while installing Mason tools")
end

if next(failed) then
  local names = vim.tbl_keys(failed)
  table.sort(names)
  error("Mason failed to install: " .. table.concat(names, ", "))
end

print("Mason tools are ready")
