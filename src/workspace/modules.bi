'' ############################################################################
''  workspace/modules.bi -- where a tiko `#import` leads
'' ############################################################################
''
''  tiko-lang's module system (its ADR 0017): a MODULE is a directory whose files
''  each begin `#module "name"`, and `#import "acme/net/http"` names one. This
''  finds the directory an import names, following tiko-lang's RFC-0007 section 3 --
''  implemented HERE, independently, because the server never runs the compiler:
''
''    1. a path beginning `./` or `../`, against the importing file's directory
''    2. the importing file's own package: the nearest tiko.toml above it, when
''       its [package] name is the path's first segment
''    3. that manifest's [dependencies] -- `x = { path = "..." }`
''    4. each workspace folder, standing in for tiko's -i directories, which the
''       server is never told
''    5. the toolchain's pkg/: TKO_PKG, else beside a `tiko` found on PATH
''
''  `std` skips 2-4: it is always the toolchain's.
''
''  WHEN A COMPILER IS CONFIGURED (metadata.bi) its answer comes FIRST: the
''  directory it resolved the chain to, ahead of 2; the -i roots it really
''  searched, ahead of the workspace folders in 4; and its pkg/ in 5. Everything
''  above stays, behind it, as the fallback.
''
''  The answer is a list of CANDIDATES, in that order. Which of them holds the
''  module is the index's question -- it knows which files it has.
'' ----------------------------------------------------------------------------

#pragma once

#include once "workspace.bi"

'' The directories `importPath`, imported from the file at `importerPath`, may
'' name, first choice first. Native, absolute, not necessarily there.
declare sub ModuleCandidates( byref importerPath as string, byref importPath as string, _
                              byref roots as PathArray, byref outDirs as PathArray )

'' The nearest directory at or above `dir_` holding a tiko.toml, or "".
declare function ManifestDirAbove( byref dir_ as string ) as string

'' The toolchain's package tree, or "" when none can be found. First choice first: what the
'' client configured (initializationOptions.packagePaths -- SetConfiguredPackageDirs), then
'' the configured compiler's own (metadata.bi), then a `pkg` BESIDE a configured include directory (a packaged toolchain is <dir>/inc and
'' <dir>/pkg, so naming the one finds the other), then TKO_PKG, then beside a `tiko` on PATH.
declare function ToolchainPkgDir( ) as string

'' Records the client's `packagePaths`. Same rule as SetConfiguredIncludeDirs: called once,
'' from `initialize`, before the index worker starts.
declare sub SetConfiguredPackageDirs( byref dirs as PathArray )

'' THE TOOLCHAIN'S HEADER DIRECTORY, as the compiler finds it (tiko-lang cmdline.bas,
'' AppendDefaultIncludeDir): TKO_INCLUDE, else <dir>/inc or <dir>/../inc beside a `tiko` on
'' PATH; "" when there is none. A std facade includes `fb/...` headers from here.
declare function ToolchainIncDir( ) as string

'' THE DIRECTORIES A WORKSPACE'S INCLUDES ARE LOOKED UP IN after the includer's own
'' directory and the workspace folders, first choice first: what the client configured
'' (initializationOptions.includePaths -- SetConfiguredIncludeDirs), else the configured
'' compiler's (metadata.bi), else ToolchainIncDir.
'' Empty when there is neither. Only directories that exist are returned.
declare function ToolchainIncDirs( ) as PathArray

'' Records the client's `includePaths`. Called once, from `initialize` -- BEFORE the index
'' worker is started, so the thread start orders the write before every read and the worker
'' needs no lock. A later call would race the worker; there is none.
declare sub SetConfiguredIncludeDirs( byref dirs as PathArray )
