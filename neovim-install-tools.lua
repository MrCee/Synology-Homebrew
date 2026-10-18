-- Install the language servers/formatters selected by the active configuration.
-- Mason's headless command waits for installs and exits nonzero on failures.
local registry = require('mason-registry')
registry.refresh()
local specs = dofile(vim.fn.stdpath('config') .. '/lua/mrcee/plugins/lsp/mason.lua')
local mapping = require('mason-lspconfig.mappings').get_mason_map().lspconfig_to_package
local packages = {}
for _, spec in ipairs(specs) do
  for _, name in ipairs((spec.opts or {}).ensure_installed or {}) do
    local package = name
    if spec[1]:match('mason%-lspconfig') then
      package = assert(mapping[name], 'No Mason package mapping for ' .. name)
    end
    if not vim.tbl_contains(packages, package) then table.insert(packages, package) end
  end
end
local missing = {}
for _, name in ipairs(packages) do
  if not registry.get_package(name):is_installed() then table.insert(missing, name) end
end
if #missing > 0 then
  local ok, err = pcall(vim.cmd, 'MasonInstall ' .. table.concat(missing, ' '))
  local failed = {}
  for _, name in ipairs(packages) do
    if not registry.get_package(name):is_installed() then table.insert(failed, name) end
  end
  if #failed > 0 then error('Mason tools missing: ' .. table.concat(failed, ', ') .. (ok and '' or ': ' .. tostring(err))) end
end
print('Verified ' .. #packages .. ' configured Mason tools.')
