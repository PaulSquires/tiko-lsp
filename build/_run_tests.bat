@echo off
rem ===========================================================================
rem  Build and run the whole test suite (Windows x64).
rem
rem    1. tests\test_framing.bas    the base-protocol byte parser
rem    2. tests\test_json.bas       the JSON facade and the JSON-RPC model
rem    3. tests\test_position.bas   the line index and UTF-16 conversion
rem    4. tests\test_document.bas   URIs, the document model, the manager
rem    5. the piped session         a real tiko-lsp.exe, driven over a pipe
rem ===========================================================================
setlocal enabledelayedexpansion

set ROOT=%~dp0..
set FBC=C:\dev\fbc-modern\toolchains\fbc-modern-windows\fbc64.exe
set YYJSON=C:\dev\yyjson

if not "%TIKO_LSP_FBC%"==""    set FBC=%TIKO_LSP_FBC%
if not "%TIKO_LSP_YYJSON%"=="" set YYJSON=%TIKO_LSP_YYJSON%

set INC=-i "%YYJSON%\inc" -p "%YYJSON%\lib\win64"
set FAILED=0

if not exist "%ROOT%\bin" mkdir "%ROOT%\bin"

echo [1/6] building the server
call "%~dp0_compile.bat" || exit /b 1

echo [2/6] framing tests
"%FBC%" -w all %INC% "%ROOT%\tests\test_framing.bas" ^
    "%ROOT%\src\rpc\transport.bas" "%ROOT%\src\utils\logging.bas" ^
    -x "%ROOT%\bin\test_framing.exe" || exit /b 1
"%ROOT%\bin\test_framing.exe" || set FAILED=1

echo [3/6] json and json-rpc tests
"%FBC%" -w all %INC% "%ROOT%\tests\test_json.bas" ^
    "%ROOT%\src\json\json.bas" "%ROOT%\src\rpc\jsonrpc.bas" "%ROOT%\src\utils\logging.bas" ^
    -x "%ROOT%\bin\test_json.exe" || exit /b 1
"%ROOT%\bin\test_json.exe" || set FAILED=1

echo [4/6] position tests
"%FBC%" -w all %INC% "%ROOT%\tests\test_position.bas" ^
    "%ROOT%\src\utils\position.bas" ^
    -x "%ROOT%\bin\test_position.exe" || exit /b 1
"%ROOT%\bin\test_position.exe" || set FAILED=1

echo [5/6] uri and document tests
"%FBC%" -w all %INC% "%ROOT%\tests\test_document.bas" ^
    "%ROOT%\src\document\document.bas" "%ROOT%\src\document\document_manager.bas" ^
    "%ROOT%\src\utils\position.bas" "%ROOT%\src\utils\uri.bas" "%ROOT%\src\utils\logging.bas" ^
    -x "%ROOT%\bin\test_document.exe" || exit /b 1
"%ROOT%\bin\test_document.exe" || set FAILED=1

echo [6/6] piped session against the real server
"%FBC%" -w all %INC% "%ROOT%\tests\session_tool.bas" ^
    "%ROOT%\src\json\json.bas" "%ROOT%\src\rpc\transport.bas" "%ROOT%\src\rpc\jsonrpc.bas" ^
    "%ROOT%\src\lsp\protocol.bas" "%ROOT%\src\utils\logging.bas" ^
    -x "%ROOT%\bin\session_tool.exe" || exit /b 1

"%ROOT%\bin\session_tool.exe" --write "%ROOT%\bin\session.bin" || exit /b 1

rem stderr is discarded here only to keep the transcript readable; the server
rem writes diagnostics there, never to stdout.
"%ROOT%\bin\tiko-lsp.exe" --log-level info < "%ROOT%\bin\session.bin" > "%ROOT%\bin\captured.bin" 2>"%ROOT%\bin\server.log"
set SERVER_EXIT=!errorlevel!

if not "!SERVER_EXIT!"=="0" (
    echo    FAIL  the server exited with !SERVER_EXIT!, expected 0 after shutdown+exit
    set FAILED=1
) else (
    echo    ok    the server exited 0 after shutdown+exit
)

"%ROOT%\bin\session_tool.exe" --check "%ROOT%\bin\captured.bin" || set FAILED=1

echo.
if "!FAILED!"=="0" (
    echo ALL SUITES PASSED
    exit /b 0
)
echo SUITE FAILURES -- see above
exit /b 1
