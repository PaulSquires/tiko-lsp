-- tiko.nvim: runs tiko-lsp for tiko files in Neovim.
--
-- The plugin does almost nothing, and that is the point: Neovim speaks LSP,
-- tiko-lsp speaks LSP, and all that is missing between them is a filetype
-- called tiko and the path to a binary. Everything a user sees -- diagnostics,
-- completion, hover, rename, formatting, semantic colour -- comes from the
-- server over the wire, not from here. It is the Neovim twin of ../zed,
-- ../vscode and ../sublime, and finds the server the same way.
--
-- WHERE THE BINARY COMES FROM, in order:
--
--   1. `server_path` passed to setup() -- the escape hatch for anyone whose
--      build lives somewhere unusual;
--   2. the server inside the tiko toolchain named by `toolchain_path` -- a tiko
--      release carries it: tiko-lang/tiko-lsp.exe on Windows, tiko-lang/bin/tiko-lsp
--      elsewhere;
--   3. `tiko-lsp` on the PATH -- where a toolchain's server already is for
--      anyone who put tiko on the PATH, since it sits beside the compiler;
--   4. the server inside a tiko-lang folder where tiko-lang.net's instructions
--      leave one: the home folder, Downloads (and one level below it, where
--      Windows' Extract All puts an archive), C:/tiko-lang, /opt/tiko-lang,
--      ~/.local/tiko-lang -- the places tiko-lsp itself looks for a toolchain;
--   5. `bin/tiko-lsp(.exe)` under the project root, so that opening the
--      tiko-lsp repository itself just works after a build.
--
-- If none of those finds it, the plugin says so ONCE and what to set -- an
-- editor that silently offers no completions is the worst outcome here.
--
--   require('tiko').setup({ toolchain_path = 'C:/tiko-lang' })   -- or setup({})

local M = {}

local SERVER_NAME = 'tiko-lsp'
local IS_WINDOWS = vim.fn.has('win32') == 1
local EXE = IS_WINDOWS and (SERVER_NAME .. '.exe') or SERVER_NAME

local defaults = {
  -- The tiko-lsp executable; nil: the one in toolchain_path, PATH, a tiko-lang
  -- folder in the usual places, then <root>/bin.
  server_path = nil,
  -- The folder you unpacked tiko into (tiko-lang): its server, headers, packages
  -- and compiler are used. nil: the server finds a toolchain on its own. Sent as
  -- initializationOptions.toolchainPath.
  toolchain_path = nil,
  -- Arguments passed to the server. Add '--log-level', 'debug', '--log-file',
  -- 'C:/temp/tiko-lsp.log' to see what it is doing; it never writes to stdout.
  server_arguments = { '--stdio' },
  -- The toolchain's inc: Win32, AfxNova and runtime names complete, hover and
  -- show signatures. Sent as initializationOptions.includePaths.
  include_paths = {},
  -- The toolchain's pkg (what `#import "std/strings"` names). Usually
  -- unnecessary: the pkg beside an include path is found on its own.
  package_paths = {},
  -- A tiko the server may ASK about each workspace folder's tiko.toml
  -- (`tiko metadata`): imports resolve where the compiler resolves them, and
  -- the tiko/metadata request returns the targets. Never run for diagnostics.
  -- Sent as initializationOptions.compilerPath.
  compiler_path = nil,
  -- What marks a project's root -- the workspace folder the server scans.
  root_markers = { 'tiko.toml', '.git' },
  -- Also claim the legacy FreeBASIC extensions .bas/.bi/.inc for tiko. Set to
  -- false if another plugin owns them.
  legacy_extensions = true,
}

M.config = vim.deepcopy(defaults)

local warned = false

local function is_file(p)
  local st = p and vim.uv.fs_stat(p)
  return st ~= nil and st.type == 'file'
end

--- The tiko-lsp inside a toolchain folder, either layout, or nil.
local function server_in(root)
  for _, cand in ipairs({ vim.fs.joinpath(root, EXE), vim.fs.joinpath(root, 'bin', EXE) }) do
    if is_file(cand) then return cand end
  end
  return nil
end

--- Where tiko-lang.net's instructions leave a toolchain, first choice first.
local function usual_toolchains()
  local home = vim.uv.os_homedir() or ''
  local downloads = vim.fs.joinpath(home, 'Downloads')
  local places = { vim.fs.joinpath(home, 'tiko-lang'), vim.fs.joinpath(downloads, 'tiko-lang') }
  local extracted = {}
  local st = vim.uv.fs_stat(downloads)
  for name, kind in (st and st.type == 'directory') and vim.fs.dir(downloads) or function() end do
    if kind == 'directory' and name:lower():sub(1, 5) == 'tiko-' then
      table.insert(extracted, name)
    end
  end
  table.sort(extracted)
  for _, name in ipairs(extracted) do
    table.insert(places, vim.fs.joinpath(downloads, name, 'tiko-lang'))
  end
  if IS_WINDOWS then
    table.insert(places, (os.getenv('SystemDrive') or 'C:') .. '/tiko-lang')
  else
    table.insert(places, '/opt/tiko-lang')
    table.insert(places, vim.fs.joinpath(home, '.local', 'tiko-lang'))
  end
  return places
end

--- The server binary for a project root, or nil and the reason.
function M.find_server(root)
  local configured = M.config.server_path
  -- Settings win outright: a path a user named is used even when it is wrong,
  -- because guessing past an explicit instruction is how a tool becomes
  -- impossible to point somewhere. The error then names that path.
  if configured and configured ~= '' then
    configured = vim.fn.expand(configured)
    if is_file(configured) then return configured end
    return nil, 'server_path names a file that does not exist: ' .. configured
  end

  if M.config.toolchain_path and M.config.toolchain_path ~= '' then
    local found = server_in(vim.fn.expand(M.config.toolchain_path))
    if found then return found end
  end

  local on_path = vim.fn.exepath(SERVER_NAME)
  if on_path ~= '' then return on_path end

  for _, place in ipairs(usual_toolchains()) do
    local found = server_in(place)
    if found then return found end
  end

  if root then
    local cand = vim.fs.joinpath(root, 'bin', EXE)
    if is_file(cand) then return cand end
  end
  return nil, SERVER_NAME .. ' was not found. It comes with tiko: put the tiko-lang folder (on '
    .. "Linux and macOS, its bin) on your PATH, or pass toolchain_path to require('tiko').setup()."
end

--- The project root for a buffer: the nearest root marker, else the file's directory.
function M.root_for(bufnr)
  local root = vim.fs.root(bufnr, M.config.root_markers)
  if root then return root end
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name ~= '' and vim.fs.dirname(name) or vim.uv.cwd()
end

--- What the server is told in `initialize`.
local function init_options()
  local opts = {}
  if M.config.toolchain_path and M.config.toolchain_path ~= '' then
    opts.toolchainPath = vim.fn.expand(M.config.toolchain_path)
  end
  if #M.config.include_paths > 0 then opts.includePaths = M.config.include_paths end
  if #M.config.package_paths > 0 then opts.packagePaths = M.config.package_paths end
  if M.config.compiler_path then opts.compilerPath = M.config.compiler_path end
  return opts
end

--- Starts (or reuses) the client for a buffer. vim.lsp.start reuses a running
--- client with the same name and root, so every tiko buffer of a project
--- shares one server.
function M.start(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local root = M.root_for(bufnr)
  local path, why = M.find_server(root)
  if not path then
    if not warned then
      warned = true
      vim.notify('tiko: ' .. why, vim.log.levels.WARN)
    end
    return nil
  end

  local cmd = { path }
  vim.list_extend(cmd, M.config.server_arguments)

  return vim.lsp.start({
    name = 'tiko',
    cmd = cmd,
    root_dir = root,
    init_options = init_options(),
  }, { bufnr = bufnr })
end

local function clients()
  return vim.lsp.get_clients({ name = 'tiko' })
end

--- Stops every tiko client and starts again for every tiko buffer: the way to
--- apply a change to include_paths, which a server reads only in `initialize`.
function M.restart()
  for _, c in ipairs(clients()) do c:stop() end
  vim.defer_fn(function()
    warned = false
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == 'tiko' then M.start(b) end
    end
  end, 500)
end

function M.info()
  local buf = vim.api.nvim_get_current_buf()
  local root = M.root_for(buf)
  local path, why = M.find_server(root)
  local lines = {
    'tiko-lsp:      ' .. (path or ('NOT FOUND -- ' .. why)),
    'arguments:     ' .. table.concat(M.config.server_arguments, ' '),
    'project root:  ' .. root,
    'toolchain:     ' .. (M.config.toolchain_path or '(found by the server)'),
    'include paths: ' .. (#M.config.include_paths > 0 and table.concat(M.config.include_paths, ', ') or '(none)'),
    'package paths: ' .. (#M.config.package_paths > 0 and table.concat(M.config.package_paths, ', ') or '(beside the include paths)'),
  }
  for _, c in ipairs(clients()) do
    table.insert(lines, ('client %d:      running, root %s, %d buffer(s)'):format(
      c.id, c.config.root_dir or '?', vim.tbl_count(c.attached_buffers)))
  end
  if #clients() == 0 then table.insert(lines, 'client:        not running') end
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})

  local ext = { tiko = 'tiko', tko = 'tiko', ti = 'tiko' }
  if M.config.legacy_extensions then
    ext.bas, ext.bi, ext.inc = 'tiko', 'tiko', 'tiko'
  end
  vim.filetype.add({ extension = ext })

  local group = vim.api.nvim_create_augroup('tiko_lsp', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'tiko',
    callback = function(ev) M.start(ev.buf) end,
  })

  vim.api.nvim_create_user_command('TikoRestart', M.restart, { desc = 'Restart tiko-lsp' })
  vim.api.nvim_create_user_command('TikoInfo', M.info, { desc = 'Show how tiko-lsp is started' })

  -- Buffers opened before setup() ran -- a file given on the command line --
  -- get their filetype re-detected, and so their client.
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == '' and vim.api.nvim_buf_get_name(b) ~= '' then
      vim.api.nvim_buf_call(b, function() vim.cmd('filetype detect') end)
    end
  end
end

return M
