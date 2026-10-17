'' ############################################################################
''  analysis/diagnostics.bas
'' ############################################################################

#import "std/containers"
#include once "diagnostics.bi"

sub AddDiagnostic( byref diags as DiagnosticArray, _
                   byval severity as DiagSeverity, _
                   byval startOffset as long, _
                   byval endOffset as long, _
                   byref code_ as string, _
                   byref message_ as string )

    dim as Diagnostic d
    d.Severity    = severity
    d.StartOffset = startOffset
    d.EndOffset   = endOffset
    d.Code_       = code_
    d.Message_    = message_

    if( d.StartOffset < 0 ) then d.StartOffset = 0
    if( d.EndOffset <= d.StartOffset ) then d.EndOffset = d.StartOffset + 1

    diags.Push( d )
end sub
