@echo off
rem ===========================================================================
rem  Build and run the whole test suite (Windows x64).
rem
rem    1. tests\test_framing.bas    the base-protocol byte parser
rem    2. tests\test_json.bas       the JSON facade and the JSON-RPC model
rem    3. tests\test_position.bas   the line index and UTF-16 conversion
rem    4. tests\test_document.bas   URIs, the document model, the manager
rem    5. tests\test_analysis.bas  the lexer, the parser, and this project's
rem                                 own source analysed for false positives
rem    6. tests\test_symbols.bas   symbol extraction, scope resolution, hover
rem    7. tests\test_completion.bas  context detection and candidates
rem    8. tests\test_workspace.bas   discovery, the index, reference scanning
rem    9. tests\test_signature.bas  signatures, call contexts, argument sites
rem   10. tests\test_semantic.bas   semantic tokens and their encoding
rem   11. tests\test_format.bas     re-indentation, and what it refuses
rem   12. the piped session         a real tiko-lsp.exe, driven over a pipe
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

echo [1/13] building the server
call "%~dp0_compile.bat" || exit /b 1

echo [2/13] framing tests
"%FBC%" -w all -mt %INC% "%ROOT%\tests\test_framing.bas" ^
    "%ROOT%\src\rpc\transport.bas" "%ROOT%\src\utils\logging.bas" ^
    -x "%ROOT%\bin\test_framing.exe" || exit /b 1
"%ROOT%\bin\test_framing.exe" || set FAILED=1

echo [3/13] json and json-rpc tests
"%FBC%" -w all -mt %INC% "%ROOT%\tests\test_json.bas" ^
    "%ROOT%\src\json\json.bas" "%ROOT%\src\rpc\jsonrpc.bas" "%ROOT%\src\utils\logging.bas" ^
    -x "%ROOT%\bin\test_json.exe" || exit /b 1
"%ROOT%\bin\test_json.exe" || set FAILED=1

echo [4/13] position tests
"%FBC%" -w all -mt %INC% "%ROOT%\tests\test_position.bas" ^
    "%ROOT%\src\utils\position.bas" ^
    -x "%ROOT%\bin\test_position.exe" || exit /b 1
"%ROOT%\bin\test_position.exe" || set FAILED=1

echo [5/13] uri and document tests
"%FBC%" -w all -mt %INC% "%ROOT%\tests\test_document.bas" ^
    "%ROOT%\src\document\document.bas" "%ROOT%\src\document\document_manager.bas" ^
    "%ROOT%\src\analysis\lexer.bas" "%ROOT%\src\analysis\parser.bas" ^
    "%ROOT%\src\analysis\symbols.bas" "%ROOT%\src\analysis\completion.bas" ^
    "%ROOT%\src\analysis\diagnostics.bas" ^
    "%ROOT%\src\utils\position.bas" "%ROOT%\src\utils\uri.bas" "%ROOT%\src\utils\logging.bas" ^
    -x "%ROOT%\bin\test_document.exe" || exit /b 1
"%ROOT%\bin\test_document.exe" || set FAILED=1

echo [6/13] lexer and parser tests
"%FBC%" -w all -mt %INC% "%ROOT%\tests\test_analysis.bas" ^
    "%ROOT%\src\analysis\lexer.bas" "%ROOT%\src\analysis\parser.bas" ^
    "%ROOT%\src\analysis\symbols.bas" "%ROOT%\src\analysis\completion.bas" ^
    "%ROOT%\src\analysis\diagnostics.bas" ^
    -x "%ROOT%\bin\test_analysis.exe" || exit /b 1
rem The project root is passed so the suite can analyse this project's OWN
rem source and require zero diagnostics from it.
"%ROOT%\bin\test_analysis.exe" "%ROOT%" || set FAILED=1

echo [7/13] symbol tests
"%FBC%" -w all -mt %INC% "%ROOT%\tests\test_symbols.bas" ^
    "%ROOT%\src\analysis\lexer.bas" "%ROOT%\src\analysis\parser.bas" ^
    "%ROOT%\src\analysis\symbols.bas" "%ROOT%\src\analysis\completion.bas" ^
    "%ROOT%\src\analysis\diagnostics.bas" ^
    -x "%ROOT%\bin\test_symbols.exe" || exit /b 1
"%ROOT%\bin\test_symbols.exe" || set FAILED=1

echo [8/13] completion tests
"%FBC%" -w all -mt %INC% "%ROOT%\tests\test_completion.bas" ^
    "%ROOT%\src\analysis\lexer.bas" "%ROOT%\src\analysis\parser.bas" ^
    "%ROOT%\src\analysis\symbols.bas" "%ROOT%\src\analysis\completion.bas" ^
    "%ROOT%\src\analysis\diagnostics.bas" ^
    -x "%ROOT%\bin\test_completion.exe" || exit /b 1
"%ROOT%\bin\test_completion.exe" || set FAILED=1

echo [9/13] workspace tests
"%FBC%" -w all -mt %INC% "%ROOT%\tests\test_workspace.bas" ^
    "%ROOT%\src\workspace\workspace.bas" "%ROOT%\src\workspace\symbol_index.bas" "%ROOT%\src\workspace\modules.bas" "%ROOT%\src\analysis\includes.bas" ^
    "%ROOT%\src\workspace\index_builder.bas" ^
    "%ROOT%\src\analysis\lexer.bas" "%ROOT%\src\analysis\parser.bas" ^
    "%ROOT%\src\analysis\symbols.bas" "%ROOT%\src\analysis\diagnostics.bas" ^
    "%ROOT%\src\utils\position.bas" "%ROOT%\src\utils\uri.bas" "%ROOT%\src\utils\logging.bas" ^
    -x "%ROOT%\bin\test_workspace.exe" || exit /b 1
"%ROOT%\bin\test_workspace.exe" "%ROOT%" || set FAILED=1

echo [10/13] signature tests
"%FBC%" -w all -mt %INC% "%ROOT%\tests\test_signature.bas" ^
    "%ROOT%\src\analysis\lexer.bas" "%ROOT%\src\analysis\parser.bas" ^
    "%ROOT%\src\analysis\symbols.bas" "%ROOT%\src\analysis\signature.bas" ^
    "%ROOT%\src\analysis\diagnostics.bas" "%ROOT%\src\utils\position.bas" ^
    -x "%ROOT%\bin\test_signature.exe" || exit /b 1
"%ROOT%\bin\test_signature.exe" || set FAILED=1

echo [11/13] semantic token tests
"%FBC%" -w all -mt %INC% "%ROOT%\tests\test_semantic.bas" ^
    "%ROOT%\src\analysis\lexer.bas" "%ROOT%\src\analysis\parser.bas" ^
    "%ROOT%\src\analysis\symbols.bas" "%ROOT%\src\analysis\semantic.bas" ^
    "%ROOT%\src\analysis\diagnostics.bas" "%ROOT%\src\utils\position.bas" ^
    -x "%ROOT%\bin\test_semantic.exe" || exit /b 1
"%ROOT%\bin\test_semantic.exe" || set FAILED=1

echo [12/13] formatting tests
"%FBC%" -w all -mt %INC% "%ROOT%\tests\test_format.bas" ^
    "%ROOT%\src\analysis\lexer.bas" "%ROOT%\src\analysis\parser.bas" ^
    "%ROOT%\src\analysis\symbols.bas" "%ROOT%\src\analysis\format.bas" ^
    "%ROOT%\src\analysis\diagnostics.bas" "%ROOT%\src\utils\position.bas" ^
    -x "%ROOT%\bin\test_format.exe" || exit /b 1
"%ROOT%\bin\test_format.exe" || set FAILED=1

echo [13/13] piped session against the real server
"%FBC%" -w all -mt %INC% "%ROOT%\tests\session_tool.bas" ^
    "%ROOT%\src\json\json.bas" "%ROOT%\src\rpc\transport.bas" "%ROOT%\src\rpc\jsonrpc.bas" ^
    "%ROOT%\src\lsp\protocol.bas" "%ROOT%\src\analysis\semantic.bas" ^
    "%ROOT%\src\analysis\lexer.bas" "%ROOT%\src\analysis\parser.bas" ^
    "%ROOT%\src\analysis\symbols.bas" "%ROOT%\src\analysis\diagnostics.bas" ^
    "%ROOT%\src\utils\position.bas" "%ROOT%\src\utils\logging.bas" ^
    "%ROOT%\src\utils\uri.bas" ^
    -x "%ROOT%\bin\session_tool.exe" || exit /b 1

"%ROOT%\bin\session_tool.exe" --write "%ROOT%\bin\session.bin" "%ROOT%\tests\fixtures\workspace" || exit /b 1

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
