'' ############################################################################
''  analysis/parser.bi -- structural analysis
''
''  NOT a full FreeBASIC parser. It reads the token stream statement by
''  statement and checks the things that are wrong no matter what the
''  expressions mean:
''
''      block openers and closers match, and nest              (sub/end sub)
''      ELSE, ELSEIF and CASE appear inside the right block
''      parentheses and brackets balance within a statement
''      #if / #endif and #macro / #endmacro match
''
''  plus whatever the lexer reported: unterminated strings and block comments,
''  malformed numbers, bytes that begin nothing.
''
''  It never stops at the first error. Every recovery rule is chosen so that
''  one mistake produces ONE diagnostic rather than a cascade -- a parser that
''  reports forty errors for a missing END IF is worse than one that reports
''  none, because the real problem is off screen.
''
''  Phase 4 grows this into a real parser producing an AST and a symbol table;
''  the block stack it already maintains is where those symbols come from.
'' ############################################################################

#pragma once

#include once "lexer.bi"
#include once "symbols.bi"
#include once "diagnostics.bi"

'' A document with more problems than this is being edited mid-thought, and
'' the rest of the list tells the user nothing. The cap is per analysis.
const MAX_DIAGNOSTICS = 200

'' Tokens in, diagnostics out, and symbols too when a table is supplied.
'' `text_` is needed for identifier names.
declare sub ParseTokens( byref text_ as string, byref tokens as TokenArray, _
                         byref diags as DiagnosticArray, _
                         byval symbols as SymbolTable ptr = 0 )

'' Lex and parse in one call, for a caller that only wants problems.
declare sub AnalyzeSource( byref text_ as string, byref diags as DiagnosticArray )

'' Lex and parse in one call, keeping the tokens and the symbols. This is what
'' a document's cached analysis uses -- hover, definition and the outline all
'' need the tokens as well as the table.
declare sub AnalyzeFull( byref text_ as string, byref tokens as TokenArray, _
                         byref diags as DiagnosticArray, byref symbols as SymbolTable )
