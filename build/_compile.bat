@echo off
rem ===========================================================================
rem  Build bin\tiko-lsp.exe (Windows x64).
rem
rem  Requires:
rem    tiko         C:\dev\tiko-lang\toolchains\tiko-windows\tiko.exe
rem    yyjson       C:\dev\yyjson  (bin\yyjson64.dll must already be built)
rem
rem  Override either with TIKO_LSP_TIKO / TIKO_LSP_YYJSON.
rem
rem  TIKO_LSP_YYJSON_LIB names the directory yyjson is linked from instead of
rem  %YYJSON%\lib\win64. A directory holding a static libyyjson64.a (and no
rem  libyyjson64.dll.a -- tiko prefers the import library) gives an exe that
rem  needs no yyjson64.dll; build\_build_yyjson_static.sh makes one, and the
rem  release build uses it.
rem ===========================================================================
setlocal

set ROOT=%~dp0..
set TIKO=C:\dev\tiko-lang\toolchains\tiko-windows\tiko.exe
set YYJSON=C:\dev\yyjson

if not "%TIKO_LSP_TIKO%"==""   set TIKO=%TIKO_LSP_TIKO%
if not "%TIKO_LSP_YYJSON%"=="" set YYJSON=%TIKO_LSP_YYJSON%

set YYLIB=%YYJSON%\lib\win64
if not "%TIKO_LSP_YYJSON_LIB%"=="" set YYLIB=%TIKO_LSP_YYJSON_LIB%

if not exist "%TIKO%" (
    echo Compiler not found: %TIKO%
    exit /b 1
)
if exist "%YYLIB%\libyyjson64.dll.a" (
    if not exist "%YYJSON%\bin\yyjson64.dll" (
        echo yyjson64.dll not found under %YYJSON% -- run its build\_compile.bat first.
        exit /b 1
    )
) else if not exist "%YYLIB%\libyyjson64.a" (
    echo Neither libyyjson64.dll.a nor libyyjson64.a is in %YYLIB%.
    exit /b 1
)

if not exist "%ROOT%\bin" mkdir "%ROOT%\bin"

set SOURCES=^
 "%ROOT%\src\main.tiko"^
 "%ROOT%\src\json\json.tiko"^
 "%ROOT%\src\rpc\transport.tiko"^
 "%ROOT%\src\rpc\jsonrpc.tiko"^
 "%ROOT%\src\lsp\protocol.tiko"^
 "%ROOT%\src\lsp\dispatcher.tiko"^
 "%ROOT%\src\lsp\publish.tiko"^
 "%ROOT%\src\handlers\lifecycle.tiko"^
 "%ROOT%\src\handlers\text_document.tiko"^
 "%ROOT%\src\handlers\document_symbols.tiko"^
 "%ROOT%\src\handlers\hover.tiko"^
 "%ROOT%\src\handlers\definition.tiko"^
 "%ROOT%\src\handlers\completion.tiko"^
 "%ROOT%\src\handlers\workspace_symbols.tiko"^
 "%ROOT%\src\handlers\references.tiko"^
 "%ROOT%\src\handlers\rename.tiko"^
 "%ROOT%\src\handlers\signature_help.tiko"^
 "%ROOT%\src\handlers\semantic_tokens.tiko"^
 "%ROOT%\src\handlers\inlay_hints.tiko"^
 "%ROOT%\src\handlers\formatting.tiko"^
 "%ROOT%\src\handlers\code_action.tiko"^
 "%ROOT%\src\handlers\watched_files.tiko"^
 "%ROOT%\src\handlers\tiko_metadata.tiko"^
 "%ROOT%\src\document\document.tiko"^
 "%ROOT%\src\document\document_manager.tiko"^
 "%ROOT%\src\analysis\lexer.tiko"^
 "%ROOT%\src\analysis\parser.tiko"^
 "%ROOT%\src\analysis\symbols.tiko"^
 "%ROOT%\src\analysis\completion.tiko"^
 "%ROOT%\src\analysis\includes.tiko"^
 "%ROOT%\src\analysis\signature.tiko"^
 "%ROOT%\src\analysis\semantic.tiko"^
 "%ROOT%\src\analysis\format.tiko"^
 "%ROOT%\src\workspace\workspace.tiko"^
 "%ROOT%\src\workspace\symbol_index.tiko"^
 "%ROOT%\src\workspace\modules.tiko"^
 "%ROOT%\src\workspace\index_builder.tiko"^
 "%ROOT%\src\workspace\metadata.tiko"^
 "%ROOT%\src\workspace\cincludes.tiko"^
 "%ROOT%\src\utils\process.tiko"^
 "%ROOT%\src\analysis\diagnostics.tiko"^
 "%ROOT%\src\utils\logging.tiko"^
 "%ROOT%\src\utils\position.tiko"^
 "%ROOT%\src\utils\uri.tiko"

echo Building tiko-lsp.exe
"%TIKO%" -w all -mt -i "%YYJSON%\inc" -p "%YYLIB%" %SOURCES% -x "%ROOT%\bin\tiko-lsp.exe"
if errorlevel 1 (
    echo.
    echo BUILD FAILED
    exit /b 1
)

rem Linked through the import library, the server loads yyjson64.dll at run
rem time, so it has to sit beside the exe. A static link needs nothing.
if exist "%YYLIB%\libyyjson64.dll.a" copy /y "%YYJSON%\bin\yyjson64.dll" "%ROOT%\bin\" >nul

echo Built %ROOT%\bin\tiko-lsp.exe
exit /b 0
