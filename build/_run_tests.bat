@echo off
rem ===========================================================================
rem  Build and run the whole test suite (Windows x64).
rem
rem    1. tests\test_framing.tiko    the base-protocol byte parser
rem    2. tests\test_json.tiko       the JSON facade and the JSON-RPC model
rem    3. tests\test_position.tiko   the line index and UTF-16 conversion
rem    4. tests\test_document.tiko   URIs, the document model, the manager
rem    5. tests\test_analysis.tiko  the lexer, the parser, and this project's
rem                                 own source analysed for false positives
rem    6. tests\test_symbols.tiko   symbol extraction, scope resolution, hover
rem    7. tests\test_completion.tiko  context detection and candidates
rem    8. tests\test_workspace.tiko   discovery, the index, reference scanning
rem    9. tests\test_signature.tiko  signatures, call contexts, argument sites
rem   10. tests\test_semantic.tiko   semantic tokens and their encoding
rem   11. tests\test_format.tiko     re-indentation, and what it refuses
rem   12. the piped session         a real tiko-lsp.exe, driven over a pipe
rem ===========================================================================
setlocal enabledelayedexpansion

set ROOT=%~dp0..
set TIKO=C:\dev\tiko-lang\toolchains\tiko-windows\tiko.exe
set YYJSON=C:\dev\yyjson

if not "%TIKO_LSP_TIKO%"==""   set TIKO=%TIKO_LSP_TIKO%
if not "%TIKO_LSP_YYJSON%"=="" set YYJSON=%TIKO_LSP_YYJSON%

rem TIKO_LSP_YYJSON_LIB: see _compile.bat. The suite links what the server links.
set YYLIB=%YYJSON%\lib\win64
if not "%TIKO_LSP_YYJSON_LIB%"=="" set YYLIB=%TIKO_LSP_YYJSON_LIB%
set INC=-i "%YYJSON%\inc" -p "%YYLIB%"
set FAILED=0

if not exist "%ROOT%\bin" mkdir "%ROOT%\bin"

echo [1/13] building the server
call "%~dp0_compile.bat" || exit /b 1

echo [2/13] framing tests
"%TIKO%" -w all -mt %INC% "%ROOT%\tests\test_framing.tiko" ^
    "%ROOT%\src\rpc\transport.tiko" "%ROOT%\src\utils\logging.tiko" ^
    -x "%ROOT%\bin\test_framing.exe" || exit /b 1
"%ROOT%\bin\test_framing.exe" || set FAILED=1

echo [3/13] json and json-rpc tests
"%TIKO%" -w all -mt %INC% "%ROOT%\tests\test_json.tiko" ^
    "%ROOT%\src\json\json.tiko" "%ROOT%\src\rpc\jsonrpc.tiko" "%ROOT%\src\utils\logging.tiko" ^
    -x "%ROOT%\bin\test_json.exe" || exit /b 1
"%ROOT%\bin\test_json.exe" || set FAILED=1

echo [4/13] position tests
"%TIKO%" -w all -mt %INC% "%ROOT%\tests\test_position.tiko" ^
    "%ROOT%\src\utils\position.tiko" ^
    -x "%ROOT%\bin\test_position.exe" || exit /b 1
"%ROOT%\bin\test_position.exe" || set FAILED=1

echo [5/13] uri and document tests
"%TIKO%" -w all -mt %INC% "%ROOT%\tests\test_document.tiko" ^
    "%ROOT%\src\document\document.tiko" "%ROOT%\src\document\document_manager.tiko" ^
    "%ROOT%\src\analysis\lexer.tiko" "%ROOT%\src\analysis\parser.tiko" ^
    "%ROOT%\src\analysis\symbols.tiko" "%ROOT%\src\analysis\completion.tiko" ^
    "%ROOT%\src\analysis\diagnostics.tiko" ^
    "%ROOT%\src\utils\position.tiko" "%ROOT%\src\utils\uri.tiko" "%ROOT%\src\utils\logging.tiko" ^
    -x "%ROOT%\bin\test_document.exe" || exit /b 1
"%ROOT%\bin\test_document.exe" || set FAILED=1

echo [6/13] lexer and parser tests
"%TIKO%" -w all -mt %INC% "%ROOT%\tests\test_analysis.tiko" ^
    "%ROOT%\src\analysis\lexer.tiko" "%ROOT%\src\analysis\parser.tiko" ^
    "%ROOT%\src\analysis\symbols.tiko" "%ROOT%\src\analysis\completion.tiko" ^
    "%ROOT%\src\analysis\diagnostics.tiko" ^
    -x "%ROOT%\bin\test_analysis.exe" || exit /b 1
rem The project root is passed so the suite can analyse this project's OWN
rem source and require zero diagnostics from it.
"%ROOT%\bin\test_analysis.exe" "%ROOT%" || set FAILED=1

echo [7/13] symbol tests
"%TIKO%" -w all -mt %INC% "%ROOT%\tests\test_symbols.tiko" ^
    "%ROOT%\src\analysis\lexer.tiko" "%ROOT%\src\analysis\parser.tiko" ^
    "%ROOT%\src\analysis\symbols.tiko" "%ROOT%\src\analysis\completion.tiko" ^
    "%ROOT%\src\analysis\diagnostics.tiko" ^
    -x "%ROOT%\bin\test_symbols.exe" || exit /b 1
"%ROOT%\bin\test_symbols.exe" || set FAILED=1

echo [8/13] completion tests
"%TIKO%" -w all -mt %INC% "%ROOT%\tests\test_completion.tiko" ^
    "%ROOT%\src\analysis\lexer.tiko" "%ROOT%\src\analysis\parser.tiko" ^
    "%ROOT%\src\analysis\symbols.tiko" "%ROOT%\src\analysis\completion.tiko" ^
    "%ROOT%\src\analysis\diagnostics.tiko" ^
    -x "%ROOT%\bin\test_completion.exe" || exit /b 1
"%ROOT%\bin\test_completion.exe" || set FAILED=1

echo [9/13] workspace tests
rem tests\fake_tiko stands in for `tiko metadata`, here and in the metadata session.
"%TIKO%" -w all "%ROOT%\tests\fake_tiko.tiko" -x "%ROOT%\bin\fake_tiko.exe" || exit /b 1
"%TIKO%" -w all -mt %INC% "%ROOT%\tests\test_workspace.tiko" ^
    "%ROOT%\src\workspace\workspace.tiko" "%ROOT%\src\workspace\symbol_index.tiko" "%ROOT%\src\workspace\modules.tiko" "%ROOT%\src\analysis\includes.tiko" ^
    "%ROOT%\src\workspace\index_builder.tiko" "%ROOT%\src\workspace\metadata.tiko" "%ROOT%\src\workspace\cincludes.tiko" ^
    "%ROOT%\src\utils\process.tiko" "%ROOT%\src\json\json.tiko" ^
    "%ROOT%\src\analysis\lexer.tiko" "%ROOT%\src\analysis\parser.tiko" ^
    "%ROOT%\src\analysis\symbols.tiko" "%ROOT%\src\analysis\diagnostics.tiko" ^
    "%ROOT%\src\utils\position.tiko" "%ROOT%\src\utils\uri.tiko" "%ROOT%\src\utils\logging.tiko" ^
    -x "%ROOT%\bin\test_workspace.exe" || exit /b 1
"%ROOT%\bin\test_workspace.exe" "%ROOT%" || set FAILED=1

echo [10/13] signature tests
"%TIKO%" -w all -mt %INC% "%ROOT%\tests\test_signature.tiko" ^
    "%ROOT%\src\analysis\lexer.tiko" "%ROOT%\src\analysis\parser.tiko" ^
    "%ROOT%\src\analysis\symbols.tiko" "%ROOT%\src\analysis\signature.tiko" ^
    "%ROOT%\src\analysis\diagnostics.tiko" "%ROOT%\src\utils\position.tiko" ^
    -x "%ROOT%\bin\test_signature.exe" || exit /b 1
"%ROOT%\bin\test_signature.exe" || set FAILED=1

echo [11/13] semantic token tests
"%TIKO%" -w all -mt %INC% "%ROOT%\tests\test_semantic.tiko" ^
    "%ROOT%\src\analysis\lexer.tiko" "%ROOT%\src\analysis\parser.tiko" ^
    "%ROOT%\src\analysis\symbols.tiko" "%ROOT%\src\analysis\semantic.tiko" ^
    "%ROOT%\src\analysis\diagnostics.tiko" "%ROOT%\src\utils\position.tiko" ^
    -x "%ROOT%\bin\test_semantic.exe" || exit /b 1
"%ROOT%\bin\test_semantic.exe" || set FAILED=1

echo [12/13] formatting tests
"%TIKO%" -w all -mt %INC% "%ROOT%\tests\test_format.tiko" ^
    "%ROOT%\src\analysis\lexer.tiko" "%ROOT%\src\analysis\parser.tiko" ^
    "%ROOT%\src\analysis\symbols.tiko" "%ROOT%\src\analysis\format.tiko" ^
    "%ROOT%\src\analysis\diagnostics.tiko" "%ROOT%\src\utils\position.tiko" ^
    -x "%ROOT%\bin\test_format.exe" || exit /b 1
"%ROOT%\bin\test_format.exe" || set FAILED=1

echo [13/13] piped session against the real server
"%TIKO%" -w all -mt %INC% "%ROOT%\tests\session_tool.tiko" ^
    "%ROOT%\src\json\json.tiko" "%ROOT%\src\rpc\transport.tiko" "%ROOT%\src\rpc\jsonrpc.tiko" ^
    "%ROOT%\src\lsp\protocol.tiko" "%ROOT%\src\analysis\semantic.tiko" ^
    "%ROOT%\src\analysis\lexer.tiko" "%ROOT%\src\analysis\parser.tiko" ^
    "%ROOT%\src\analysis\symbols.tiko" "%ROOT%\src\analysis\diagnostics.tiko" ^
    "%ROOT%\src\utils\position.tiko" "%ROOT%\src\utils\logging.tiko" ^
    "%ROOT%\src\utils\uri.tiko" ^
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

rem The toolchain-header session: a second, smaller workspace whose includes
rem reach a stand-in toolchain inc through initializationOptions.includePaths.
"%ROOT%\bin\session_tool.exe" --write-inc "%ROOT%\bin\session-inc.bin" "%ROOT%\tests\fixtures\incws" "%ROOT%\tests\fixtures\toolinc" || exit /b 1
"%ROOT%\bin\tiko-lsp.exe" --log-level info < "%ROOT%\bin\session-inc.bin" > "%ROOT%\bin\captured-inc.bin" 2>"%ROOT%\bin\server-inc.log"
"%ROOT%\bin\session_tool.exe" --check-inc "%ROOT%\bin\captured-inc.bin" || set FAILED=1

rem The compiler-metadata session: tests\fixtures\meta\ws, whose one import is found only
rem through `tiko metadata` -- here tests\fake_tiko -- and then the same session with no
rem compiler, which must not find it.
"%ROOT%\bin\session_tool.exe" --write-meta "%ROOT%\bin\session-meta.bin" "%ROOT%\tests\fixtures\meta\ws" "%ROOT%\bin\fake_tiko.exe" || exit /b 1
"%ROOT%\bin\tiko-lsp.exe" --log-level info < "%ROOT%\bin\session-meta.bin" > "%ROOT%\bin\captured-meta.bin" 2>"%ROOT%\bin\server-meta.log"
"%ROOT%\bin\session_tool.exe" --check-meta "%ROOT%\bin\captured-meta.bin" || set FAILED=1
"%ROOT%\bin\session_tool.exe" --write-meta "%ROOT%\bin\session-meta-off.bin" "%ROOT%\tests\fixtures\meta\ws" "" || exit /b 1
"%ROOT%\bin\tiko-lsp.exe" --log-level info < "%ROOT%\bin\session-meta-off.bin" > "%ROOT%\bin\captured-meta-off.bin" 2>"%ROOT%\bin\server-meta-off.log"
"%ROOT%\bin\session_tool.exe" --check-meta-off "%ROOT%\bin\captured-meta-off.bin" || set FAILED=1

rem The #cinclude session: tests\fixtures\cinc\ws, whose #cinclude "fake.h" resolves only through
rem `tiko --print-cincludes` -- here tests\fake_tiko -- and the control with no compiler.
"%ROOT%\bin\session_tool.exe" --write-cinc "%ROOT%\bin\session-cinc.bin" "%ROOT%\tests\fixtures\cinc\ws" "%ROOT%\bin\fake_tiko.exe" || exit /b 1
"%ROOT%\bin\tiko-lsp.exe" --log-level info < "%ROOT%\bin\session-cinc.bin" > "%ROOT%\bin\captured-cinc.bin" 2>"%ROOT%\bin\server-cinc.log"
"%ROOT%\bin\session_tool.exe" --check-cinc "%ROOT%\bin\captured-cinc.bin" || set FAILED=1
"%ROOT%\bin\session_tool.exe" --write-cinc "%ROOT%\bin\session-cinc-off.bin" "%ROOT%\tests\fixtures\cinc\ws" "" || exit /b 1
"%ROOT%\bin\tiko-lsp.exe" --log-level info < "%ROOT%\bin\session-cinc-off.bin" > "%ROOT%\bin\captured-cinc-off.bin" 2>"%ROOT%\bin\server-cinc-off.log"
"%ROOT%\bin\session_tool.exe" --check-cinc-off "%ROOT%\bin\captured-cinc-off.bin" || set FAILED=1

echo.
if "!FAILED!"=="0" (
    echo ALL SUITES PASSED
    exit /b 0
)
echo SUITE FAILURES -- see above
exit /b 1
