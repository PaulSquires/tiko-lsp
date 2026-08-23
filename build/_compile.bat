@echo off
rem ===========================================================================
rem  Build bin\tiko-lsp.exe (Windows x64).
rem
rem  Requires:
rem    fbc-modern   C:\dev\fbc-modern\toolchains\fbc-modern-windows\fbc64.exe
rem    yyjson       C:\dev\yyjson  (bin\yyjson64.dll must already be built)
rem
rem  Override either with TIKO_LSP_FBC / TIKO_LSP_YYJSON.
rem ===========================================================================
setlocal

set ROOT=%~dp0..
set FBC=C:\dev\fbc-modern\toolchains\fbc-modern-windows\fbc64.exe
set YYJSON=C:\dev\yyjson

if not "%TIKO_LSP_FBC%"==""    set FBC=%TIKO_LSP_FBC%
if not "%TIKO_LSP_YYJSON%"=="" set YYJSON=%TIKO_LSP_YYJSON%

if not exist "%FBC%" (
    echo Compiler not found: %FBC%
    exit /b 1
)
if not exist "%YYJSON%\bin\yyjson64.dll" (
    echo yyjson64.dll not found under %YYJSON% -- run its build\_compile.bat first.
    exit /b 1
)

if not exist "%ROOT%\bin" mkdir "%ROOT%\bin"

set SOURCES=^
 "%ROOT%\src\main.bas"^
 "%ROOT%\src\json\json.bas"^
 "%ROOT%\src\rpc\transport.bas"^
 "%ROOT%\src\rpc\jsonrpc.bas"^
 "%ROOT%\src\lsp\protocol.bas"^
 "%ROOT%\src\lsp\dispatcher.bas"^
 "%ROOT%\src\lsp\publish.bas"^
 "%ROOT%\src\handlers\lifecycle.bas"^
 "%ROOT%\src\handlers\text_document.bas"^
 "%ROOT%\src\handlers\document_symbols.bas"^
 "%ROOT%\src\handlers\hover.bas"^
 "%ROOT%\src\handlers\definition.bas"^
 "%ROOT%\src\handlers\completion.bas"^
 "%ROOT%\src\handlers\workspace_symbols.bas"^
 "%ROOT%\src\handlers\references.bas"^
 "%ROOT%\src\document\document.bas"^
 "%ROOT%\src\document\document_manager.bas"^
 "%ROOT%\src\analysis\lexer.bas"^
 "%ROOT%\src\analysis\parser.bas"^
 "%ROOT%\src\analysis\symbols.bas"^
 "%ROOT%\src\analysis\completion.bas"^
 "%ROOT%\src\workspace\workspace.bas"^
 "%ROOT%\src\workspace\symbol_index.bas"^
 "%ROOT%\src\analysis\diagnostics.bas"^
 "%ROOT%\src\utils\logging.bas"^
 "%ROOT%\src\utils\position.bas"^
 "%ROOT%\src\utils\uri.bas"

echo Building tiko-lsp.exe
"%FBC%" -w all -i "%YYJSON%\inc" -p "%YYJSON%\lib\win64" %SOURCES% -x "%ROOT%\bin\tiko-lsp.exe"
if errorlevel 1 (
    echo.
    echo BUILD FAILED
    exit /b 1
)

rem The server loads yyjson64.dll at run time, so it has to sit beside the exe.
copy /y "%YYJSON%\bin\yyjson64.dll" "%ROOT%\bin\" >nul

echo Built %ROOT%\bin\tiko-lsp.exe
exit /b 0
