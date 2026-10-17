'' ############################################################################
''  analysis/completion.bi -- what could be typed here
''
''  Two questions, in order:
''
''    1. WHERE IS THE CURSOR? After a dot, the answer is the members of
''       whatever is on the left. Anywhere else, it is everything in scope.
''       Getting this wrong is worse than returning nothing: an editor that
''       offers `Sub` and `Print` after `customer.` is offering nonsense.
''
''    2. WHAT IS IN SCOPE THERE? Locals and parameters of the enclosing
''       procedure, the members of the enclosing type, the file's own
''       declarations, and -- last, because they are never what you meant to
''       type -- the language's 247 reserved words.
''
''  No LSP types appear here. The handler turns these records into
''  CompletionItems; this module could feed a terminal just as well.
'' ############################################################################

#pragma once

#include once "symbols.bi"

'' LSP's CompletionItemKind, on the wire unchanged.
enum CompletionKind
    CMP_TEXT          = 1
    CMP_METHOD        = 2
    CMP_FUNCTION      = 3
    CMP_CONSTRUCTOR   = 4
    CMP_FIELD         = 5
    CMP_VARIABLE      = 6
    CMP_CLASS         = 7
    CMP_INTERFACE     = 8
    CMP_MODULE        = 9
    CMP_PROPERTY      = 10
    CMP_UNIT          = 11
    CMP_VALUE         = 12
    CMP_ENUM          = 13
    CMP_KEYWORD       = 14
    CMP_SNIPPET       = 15
    CMP_COLOR         = 16
    CMP_FILE          = 17
    CMP_REFERENCE     = 18
    CMP_FOLDER        = 19
    CMP_ENUMMEMBER    = 20
    CMP_CONSTANT      = 21
    CMP_STRUCT        = 22
    CMP_EVENT         = 23
    CMP_OPERATOR      = 24
    CMP_TYPEPARAMETER = 25
end enum

'' Sort groups. A client sorts on sortText, so the group number is what puts a
'' local above a keyword no matter what the alphabet says.
enum CompletionGroup
    CMPGROUP_MEMBER  = 0   '' members of the thing before the dot
    CMPGROUP_LOCAL   = 1   '' locals and parameters of this procedure
    CMPGROUP_TYPE    = 2   '' members of the enclosing type
    CMPGROUP_FILE    = 3   '' everything else this file declares
    CMPGROUP_INCLUDE = 4   '' what the files this one #includes declare
    CMPGROUP_KEYWORD = 5   '' the language itself
end enum

type CompletionItem
    Label     as string
    Kind_     as CompletionKind
    Detail_   as string
    Doc_      as string
    SortGroup as CompletionGroup

    '' Carried so the duplicate check does not have to lower-case both sides
    '' of every comparison. With 250 keywords and a linear scan that was two
    '' string allocations per comparison and most of the time in the call.
    LowerLabel as string
end type

type CompletionItemArray as containers.Array( of CompletionItem )

'' What the cursor is sitting in.
enum CompletionContextKind
    CMPCTX_SCOPE  = 0   '' an ordinary identifier position
    CMPCTX_MEMBER = 1   '' immediately after `something.`
    CMPCTX_NONE   = 2   '' inside a comment or a string: nothing to offer
end enum

'' A generic does not instantiate as a TYPE field; its alias does.
type CompletionChain as containers.Array( of string )

type CompletionContext
    Kind_      as CompletionContextKind
    Prefix     as string   '' the partial word already typed, lower-cased
    BaseName   as string   '' for a member context: the FIRST name of the chain left of the dot
    BaseOffset as long     '' where that base token starts, for resolution
    '' The names between the base and the last dot, lower-cased, in order:
    '' `lg.Warn( ).Str( "k", v ).` has base `lg` and chain warn, str. Empty
    '' for a plain `cfg.`. A call's arguments are skipped, not read.
    Chain      as CompletionChain
end type

'' Works out the context at `offset`. Never fails: a position in the middle of
'' a string, a comment or nothing at all comes back as CMPCTX_SCOPE with an
'' empty prefix.
declare function CompletionContextAt( byref text_ as string, byref tokens as TokenArray, _
                                      byval offset as long ) as CompletionContext

'' The member chain ending at the dot token `dotIdx` -- `lg.Warn( ).Str( k, v ).`
'' -- into ctx.BaseName, BaseOffset and Chain. Arguments are skipped, not read.
'' False when no name stands left of the dot: `(a + b).`.
declare function ReadMemberChain( byref text_ as string, byref tokens as TokenArray, _
                                  byval dotIdx as long, byref ctx as CompletionContext ) as boolean

'' The candidates at `offset`. `keywords` may be false to leave the reserved
'' words out, which is what a member context wants.
declare sub CollectCompletions( byref text_ as string, byref tokens as TokenArray, _
                                byref syms as SymbolTable, byval offset as long, _
                                byref items as CompletionItemArray )

'' The declared type NAME of a symbol, taken from its detail: `as Customer ptr`
'' yields `Customer`. "" when there is none to read.
'' Whether a member of a type belongs in an `obj.` list. Not its constructor,
'' destructor or operators: `lg.constructor` is no call anyone can write, and a
'' type with a full set of them (FB.Logger_) put them at the top of the list.
declare function IsOfferedMember( byref sym as SymbolInfo ) as boolean

declare function DeclaredTypeName( byref sym as SymbolInfo ) as string

'' The type NAME a procedure returns, from its signature: `( k as ustring )
'' byref as LogEvent` yields `LogEvent`. "" for a sub, or no procedure.
declare function ReturnTypeName( byref sym as SymbolInfo ) as string

'' The type an expression ending in this symbol has: a procedure's return type,
'' anything else's declared type. What a member chain is walked by.
declare function MemberTypeName( byref sym as SymbolInfo ) as string

'' Inside a method, the container it belongs to (inline or `sub T.M`); -1.
declare function EnclosingTypeIndex( byref syms as SymbolTable, byval offset as long ) as long

'' SymbolKind -> CompletionItemKind.
declare function CompletionKindOf( byval kind as SymbolKind ) as CompletionKind
