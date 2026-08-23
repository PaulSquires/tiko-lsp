'' ############################################################################
''  analysis/signature.bi -- calls, and the parameters they are filling in
''
''  Two questions, both answered from the token stream and the symbol table
''  that already exist:
''
''      "the caret is inside a call -- which call, and which argument?"
''      "this procedure's detail says (byval a as long) -- what are the parts?"
''
''  Signature help needs the first, inlay hints need both, and neither needs a
''  new kind of analysis. A procedure's signature was recorded as TEXT when it
''  was declared (SymbolInfo.Detail_, rebuilt from the tokens), so splitting it
''  back into parameters is a string operation on something the parser already
''  normalised -- not a second parse of the source.
''
''  WHAT THIS DOES NOT DO: overload resolution. FreeBASIC lets a name carry
''  several signatures, and choosing between them needs the types of the
''  arguments -- which needs the type system this server does not have. The
''  first matching declaration is used and the count of alternatives is
''  reported, so a client can show "1 of 3" rather than pretending there is
''  only one.
'' ############################################################################

#pragma once

#include once "fb/array.bi"
#include once "lexer.bi"
#include once "symbols.bi"

'' ----------------------------------------------------------------------------
''  One parameter of a signature
'' ----------------------------------------------------------------------------
type SigParam
    Label   as string      '' as it appears in the signature: "byval a as long"
    Name_   as string      '' just the identifier: "a"

    '' Where the label sits inside the full signature label, in UTF-16 code
    '' units. LSP lets a ParameterInformation carry either a substring or a
    '' [start, end) pair, and the pair is what a client highlights exactly --
    '' a substring match would light up the wrong `a` in `(byval a as any ptr)`.
    LabelStart as long
    LabelEnd   as long
end type

type SigParamArray as FB.Array( of SigParam )

'' Splits a procedure's Detail_ into parameters.
''
'' `detail` is what the parser recorded: "(byval a as long, byref b as string)
'' as long", or "()" for a procedure with none, or something that is not a
'' parameter list at all when the symbol is a variable. False in that last
'' case, which is how a caller tells "no parameters" from "not a procedure".
''
'' `fullLabel` comes back as the label a client should display: the name with
'' the detail after it. The LabelStart/LabelEnd of each parameter index into
'' THAT string, so the caller must not build its own.
declare function ParseSignature( byref name_ as string, byref detail as string, _
                                 byref fullLabel as string, _
                                 byref params as SigParamArray ) as boolean

'' ----------------------------------------------------------------------------
''  The call the caret is inside
'' ----------------------------------------------------------------------------
type CallContext
    Found     as boolean
    NameTok   as long      '' token index of the callee's identifier
    OpenTok   as long      '' token index of its '('
    ActiveArg as long      '' 0-based; commas at the call's own depth
    ArgTok    as long      '' first token of the active argument, or -1
end type

'' Walks BACK from `offset` to the innermost unclosed '(' on the same logical
'' line and reports what is being called.
''
'' Backwards, not forwards, because the interesting call is the one that is
'' still open: at `Sum( a, Max( b, |` the answer is Max, not Sum. Nested calls
'' fall out of the depth counter rather than needing a stack.
''
'' The search stops at the start of the LOGICAL line -- a continuation with `_`
'' produces no TK_EOL, so a signature split over three lines still resolves,
'' while a stray '(' twenty lines up cannot swallow the file.
declare function FindCallContext( byref text_ as string, byref tokens as TokenArray, _
                                  byval offset as long, byref ctx as CallContext ) as boolean

'' ----------------------------------------------------------------------------
''  Every argument of every call in a byte range
'' ----------------------------------------------------------------------------

'' One argument of one call site: flat, one entry per argument, so no array
'' has to live inside another.
type ArgSite
    NameTok  as long       '' the callee's identifier
    ArgIndex as long       '' 0-based position in the argument list
    ArgTok   as long       '' first token of the argument itself
end type

type ArgSiteArray as FB.Array( of ArgSite )

'' Collects the arguments of every call whose callee identifier lies within
'' [startOffset, endOffset). Used by inlay hints, which are asked for one
'' visible range at a time and must not analyse the rest of the file.
''
'' A "call" here is an identifier followed immediately by '(' -- which is also
'' what an array subscript and a cast look like. Whether it is really a call
'' is decided later, by whether the name resolves to a procedure.
declare sub FindArgSites( byref text_ as string, byref tokens as TokenArray, _
                          byval startOffset as long, byval endOffset as long, _
                          byref sites as ArgSiteArray )

'' The index of the best procedure declaration for `lowerName` in `symbols`,
'' visible from `fromOffset`, or -1. `alternatives` comes back with how many
'' declarations of that name were found -- the overload count a client shows.
''
'' A BODY beats a DECLARE prototype: both carry the same signature, but the
'' body is where the user wants to be sent and is the one that is definitely
'' compiled.
declare function FindCallable( byref symbols as SymbolTable, byref lowerName as string, _
                               byval fromOffset as long, byref alternatives as long ) as long

'' True when `kind` is something that can be called.
declare function IsCallableKind( byval kind as SymbolKind ) as boolean
