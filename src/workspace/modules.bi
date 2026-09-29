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
''  The answer is a list of CANDIDATES, in that order. Which of them holds the
''  module is the index's question -- it knows which files it has.
'' ----------------------------------------------------------------------------

#pragma once

#include once "workspace.bi"

'' The directories `importPath`, imported from the file at `importerPath`, may
'' name, first choice first. Native, absolute, not necessarily there.
declare sub ModuleCandidates( byref importerPath as string, byref importPath as string, _
                              byref roots as PathArray, byref outDirs as PathArray )

'' The toolchain's package tree, or "" when none can be found.
declare function ToolchainPkgDir( ) as string

'' THE TOOLCHAIN'S HEADER DIRECTORY, as the compiler finds it (tiko-lang cmdline.bas,
'' AppendDefaultIncludeDir): TKO_INCLUDE, else <dir>/inc or <dir>/../inc beside a `tiko` on
'' PATH; "" when there is none. A std facade includes `fb/...` headers from here.
declare function ToolchainIncDir( ) as string
