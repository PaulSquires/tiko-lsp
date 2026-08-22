'' ############################################################################
''  analysis/diagnostics.bi -- one problem found in one document
''
''  Deliberately free of protocol types. A diagnostic is a byte RANGE plus a
''  message; turning that into an LSP Range with UTF-16 columns happens once,
''  in the publisher, using the document's line index. The analyser never has
''  to think about position encoding, and the same diagnostic could be printed
''  to a terminal without change.
'' ############################################################################

#pragma once

#include once "fb/array.bi"

'' The values are LSP's DiagnosticSeverity and go on the wire as they are.
enum DiagSeverity
    DIAG_ERROR   = 1
    DIAG_WARNING = 2
    DIAG_INFO    = 3
    DIAG_HINT    = 4
end enum

'' What the editor shows next to the message, so a user can tell our
'' diagnostics from another tool's.
const DIAG_SOURCE = "tiko-lsp"

'' Stable machine-readable codes. A client may filter on these, so they are
'' part of the interface: add, do not rename.
const DIAGCODE_UNTERMINATED_STRING  = "unterminated-string"
const DIAGCODE_UNTERMINATED_COMMENT = "unterminated-comment"
const DIAGCODE_INVALID_NUMBER       = "invalid-number"
const DIAGCODE_UNEXPECTED_CHAR      = "unexpected-character"
const DIAGCODE_UNCLOSED_BLOCK       = "unclosed-block"
const DIAGCODE_UNEXPECTED_END       = "unexpected-end"
const DIAGCODE_MISMATCHED_END       = "mismatched-end"
const DIAGCODE_UNBALANCED_PAREN     = "unbalanced-parenthesis"
const DIAGCODE_ORPHAN_CLAUSE        = "clause-outside-block"

type Diagnostic
    Severity    as DiagSeverity
    StartOffset as long        '' byte offset, inclusive
    EndOffset   as long        '' byte offset, exclusive
    Code_       as string
    Message_    as string
end type

type DiagnosticArray as FB.Array( of Diagnostic )

'' A zero-width range is legal in LSP but invisible in most editors, so a
'' diagnostic that would be empty is widened to one byte.
declare sub AddDiagnostic( byref diags as DiagnosticArray, _
                           byval severity as DiagSeverity, _
                           byval startOffset as long, _
                           byval endOffset as long, _
                           byref code_ as string, _
                           byref message_ as string )
