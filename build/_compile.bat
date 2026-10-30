@echo off
rem ===========================================================================
rem  Build bin\tiko-lsp.exe (Windows x64).
rem
rem  Requires:
rem    tiko         C:\dev\tiko-lang\toolchains\tiko-windows\tiko.exe
rem                 (override with TIKO_LSP_TIKO)
rem
rem  JSON is cJSON, tiko's vendor/cJSON package, which the toolchain ships
rem  prebuilt; src\json\json.tiko imports it 'link static', so the exe needs
rem  nothing beside it.
rem ===========================================================================
setlocal

set ROOT=%~dp0..
set TIKO=C:\dev\tiko-lang\toolchains\tiko-windows\tiko.exe

if not "%TIKO_LSP_TIKO%"==""   set TIKO=%TIKO_LSP_TIKO%

if not exist "%TIKO%" (
    echo Compiler not found: %TIKO%
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
"%TIKO%" -w all -mt %SOURCES% -x "%ROOT%\bin\tiko-lsp.exe"
if errorlevel 1 (
    echo.
    echo BUILD FAILED
    exit /b 1
)

echo Built %ROOT%\bin\tiko-lsp.exe
exit /b 0
