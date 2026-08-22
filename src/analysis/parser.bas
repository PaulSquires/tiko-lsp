'' ############################################################################
''  analysis/parser.bas -- structural analysis
'' ############################################################################

#include once "parser.bi"

'' ----------------------------------------------------------------------------
''  One open block
'' ----------------------------------------------------------------------------
type BlockFrame
    Kind_       as FbKeyword   '' KW_SUB, KW_IF, KW_PP_IF, ...
    Name_       as string      '' "" when the block has no name
    StartOffset as long        '' the opening keyword
    EndOffset   as long
end type

type BlockStack as FB.Array( of BlockFrame )

'' The word that opens a block, for messages.
private function BlockWord( byval kw as FbKeyword ) as string
    select case kw
        case KW_SUB         : return "sub"
        case KW_FUNCTION    : return "function"
        case KW_PROPERTY    : return "property"
        case KW_CONSTRUCTOR : return "constructor"
        case KW_DESTRUCTOR  : return "destructor"
        case KW_OPERATOR    : return "operator"
        case KW_TYPE        : return "type"
        case KW_UNION       : return "union"
        case KW_ENUM        : return "enum"
        case KW_NAMESPACE   : return "namespace"
        case KW_SCOPE       : return "scope"
        case KW_WITH        : return "with"
        case KW_EXTERN      : return "extern"
        case KW_ASM         : return "asm"
        case KW_IF          : return "if"
        case KW_SELECT      : return "select"
        case KW_WHILE       : return "while"
        case KW_DO          : return "do"
        case KW_FOR         : return "for"
        case KW_PP_IF       : return "#if"
        case KW_PP_MACRO    : return "#macro"
    end select
    return "block"
end function

'' What closes it, for "expected ..." messages.
private function CloserWord( byval kw as FbKeyword ) as string
    select case kw
        case KW_WHILE    : return "wend"
        case KW_DO       : return "loop"
        case KW_FOR      : return "next"
        case KW_PP_IF    : return "#endif"
        case KW_PP_MACRO : return "#endmacro"
    end select
    return "end " & BlockWord( kw )
end function

private function DescribeFrame( byref frame as BlockFrame ) as string
    if( len(frame.Name_) > 0 ) then return "'" & BlockWord( frame.Kind_ ) & " " & frame.Name_ & "'"
    return "'" & BlockWord( frame.Kind_ ) & "'"
end function

'' ----------------------------------------------------------------------------
''  Analysis state, threaded through the statement handlers
'' ----------------------------------------------------------------------------
'' One open preprocessor conditional or macro.
''
'' These are kept OUT of the block stack, in their own, because a directive
'' does not nest with a block -- code like this is normal and correct:
''
''     #ifdef __FB_WIN32__
''         extern "C"          <- opened inside the branch
''     #else
''         extern "Windows"
''     #endif
''     ...
''     end extern              <- closed outside it
''
'' With one stack that reads as three unclosed EXTERNs. With two, the rules
'' become: at #else, drop whatever the previous branch opened; at #endif, keep
'' what the surviving branch opened; at #endmacro, drop everything, because a
'' macro body is text and is not required to balance.
type PpFrame
    Kind_       as FbKeyword   '' KW_PP_IF or KW_PP_MACRO
    Name_       as string
    StartOffset as long
    EndOffset   as long
    DepthAtOpen as long        '' block-stack depth when the directive opened
end type

type PpStack as FB.Array( of PpFrame )

'' A macro whose replacement text BEGINS A BLOCK, which fb/fslink.bi and
'' fb/string.bi both do:
''
''     #define FBFSLINK_EXTERN extern "C"
''     FBFSLINK_EXTERN
''         declare function ...
''     end extern
''
'' Without noticing the #define, that `end extern` has nothing to close. This
'' is the whole of the macro handling here: no expansion, no arguments, just
'' "this name opens that kind of block".
type MacroOpener
    Name_ as string      '' lower-cased
    Kind_ as FbKeyword
end type

type MacroOpenerArray as FB.Array( of MacroOpener )

type ParseState
    Stack_   as BlockStack
    PpStack_ as PpStack
    Macros_  as MacroOpenerArray
    Capped_  as boolean

    '' Parentheses left open by a statement that opened a lambda. The call
    '' around the lambda closes AFTER its body:
    ''
    ''     SortBy( a, function( byref x as long, byref y as long ) as boolean
    ''         return x > y
    ''     end function )
    ''                 ^ this ')' belongs to a '(' three statements back
    ''
    '' Counting them here is what keeps that from reading as two errors.
    Pending_ as long
end type

private function MacroOpenerKind( byref st as ParseState, byref name_ as string ) as FbKeyword
    dim as string want = lcase(name_)
    for i as long = 0 to st.Macros_.Count( ) - 1
        if( st.Macros_[i].Name_ = want ) then return st.Macros_[i].Kind_
    next
    return KW_NONE
end function

private sub Report( byref st as ParseState, byref diags as DiagnosticArray, _
                    byval startOffset as long, byval endOffset as long, _
                    byref code_ as string, byref message_ as string )
    '' One cap for the whole analysis. Past it the file is being edited
    '' mid-thought and the rest of the list tells the user nothing.
    if( st.Capped_ ) then exit sub

    if( diags.Count( ) >= MAX_DIAGNOSTICS ) then
        st.Capped_ = true
        AddDiagnostic( diags, DIAG_INFO, startOffset, endOffset, "too-many-diagnostics", _
                       "more than " & MAX_DIAGNOSTICS & " problems -- the rest are not listed" )
        exit sub
    end if

    AddDiagnostic( diags, DIAG_ERROR, startOffset, endOffset, code_, message_ )
end sub

'' True while the statement being read is inside a #macro body.
''
'' A macro body is a FRAGMENT, not a statement sequence: fbc's own
'' tests/structs/temp-var-dtors.bas opens a SCOPE in one macro and closes it in
'' another. Block-structure complaints there are meaningless, so they are not
'' made -- lexical ones (an unterminated string) still are.
private function InMacroBody( byref st as ParseState ) as boolean
    for i as long = 0 to st.PpStack_.Count( ) - 1
        if( st.PpStack_[i].Kind_ = KW_PP_MACRO ) then return true
    next
    return false
end function

private sub PushBlock( byref st as ParseState, byval kw as FbKeyword, _
                       byref name_ as string, byref tok as Token )
    dim as BlockFrame frame
    frame.Kind_       = kw
    frame.Name_       = name_
    frame.StartOffset = tok.Start_
    frame.EndOffset   = tok.Start_ + tok.Length_
    st.Stack_.Push( frame )
end sub

'' Closes `kw`, reporting whatever is in the way.
''
'' If the matching opener is buried under blocks that were never closed, each
'' of those is reported AT ITS OPENER -- which is where the user has to go to
'' fix it -- and then popped, so the rest of the file still analyses cleanly.
private sub CloseBlock( byref st as ParseState, byref diags as DiagnosticArray, _
                        byval kw as FbKeyword, byref tok as Token, byref closerText as string )
    dim as long found = -1
    for i as long = st.Stack_.Count( ) - 1 to 0 step -1
        if( st.Stack_[i].Kind_ = kw ) then
            found = i
            exit for
        end if
    next

    if( found < 0 ) then
        if( InMacroBody( st ) = false ) then
            Report( st, diags, tok.Start_, tok.Start_ + tok.Length_, _
                    DIAGCODE_UNEXPECTED_END, _
                    "'" & closerText & "' has no matching '" & BlockWord( kw ) & "'" )
        end if
        exit sub
    end if

    for i as long = st.Stack_.Count( ) - 1 to found + 1 step -1
        dim as BlockFrame frame = st.Stack_[i]
        if( InMacroBody( st ) ) then
            st.Stack_.Pop( )
            continue for
        end if
        Report( st, diags, frame.StartOffset, frame.EndOffset, _
                DIAGCODE_MISMATCHED_END, _
                DescribeFrame( frame ) & " is not closed -- expected '" & _
                CloserWord( frame.Kind_ ) & "' before '" & closerText & "'" )
        st.Stack_.Pop( )
    next

    st.Stack_.Pop( )
end sub

'' -- preprocessor -------------------------------------------------------------

private sub PushPp( byref st as ParseState, byval kw as FbKeyword, _
                    byref name_ as string, byref tok as Token )
    dim as PpFrame frame
    frame.Kind_       = kw
    frame.Name_       = name_
    frame.StartOffset = tok.Start_
    frame.EndOffset   = tok.Start_ + tok.Length_
    frame.DepthAtOpen = st.Stack_.Count( )
    st.PpStack_.Push( frame )
end sub

'' Drops block frames opened since `depth`, without a word. They belong to a
'' branch that is being left behind, and reporting them would be reporting on
'' code the compiler will never see together.
private sub DropBlocksTo( byref st as ParseState, byval depth as long )
    while( st.Stack_.Count( ) > depth )
        st.Stack_.Pop( )
    wend
end sub

private sub RequireInside( byref st as ParseState, byref diags as DiagnosticArray, _
                           byval kw as FbKeyword, byref tok as Token, byref clause as string )
    dim as boolean ok_ = false
    if( st.Stack_.Count( ) > 0 ) then
        ok_ = ( st.Stack_[ st.Stack_.Count( ) - 1 ].Kind_ = kw )
    end if

    if( ok_ = false andalso InMacroBody( st ) = false ) then
        Report( st, diags, tok.Start_, tok.Start_ + tok.Length_, _
                DIAGCODE_ORPHAN_CLAUSE, _
                "'" & clause & "' outside " & _
                iif( kw = KW_PP_IF, "a '#if' block", "a '" & BlockWord( kw ) & "' block" ) )
    end if
end sub

'' ----------------------------------------------------------------------------
''  Reading a name off a declaration
''
''  Handles the dotted forms -- `sub Customer.SetName` and
''  `constructor Foo.Bar` -- because the name in a diagnostic should read the
''  way the user wrote it.
'' ----------------------------------------------------------------------------
private function ReadName( byref text_ as string, byref tokens as TokenArray, _
                           byval first_ as long, byval last_ as long ) as string
    dim as string name_ = ""
    dim as long i = first_

    while( i <= last_ )
        dim as Token t = tokens[i]
        if( t.Kind = TK_IDENT ) then
            name_ &= TokenText( text_, t )
        elseif( t.Kind = TK_OP andalso TokenText( text_, t ) = "." ) then
            name_ &= "."
        else
            exit while
        end if
        i += 1
    wend

    return name_
end function

'' True when the statement has an AS outside any parentheses.
''
'' This is what separates a block from a FIELD whose name happens to be a
'' reserved word, which COM vtables are full of:
''
''     Select AS FUNCTION ( BYVAL this AS ITextRange PTR ) AS HRESULT
''
'' -- a member of ITextRangeVtbl in AfxNova's AfxTOM.bi, not a SELECT block.
private function HasTopLevelAs( byref tokens as TokenArray, _
                                byref stmt as FB.Array( of long ), byval from_ as long ) as boolean
    dim as long depth = 0
    for k as long = from_ to stmt.Count( ) - 1
        dim as Token t = tokens[ stmt[k] ]
        select case t.Kind
            case TK_LPAREN, TK_LBRACKET : depth += 1
            case TK_RPAREN, TK_RBRACKET : depth -= 1
            case TK_KEYWORD
                if( t.Kw = KW_AS andalso depth = 0 ) then return true
        end select
    next
    return false
end function

'' ----------------------------------------------------------------------------
''  Lambdas
''
''  fbc-modern's anonymous procedures open a block from inside an EXPRESSION,
''  which is the one place a block does not begin a statement:
''
''      dim as function( byref as T, byref as T ) as boolean less = _
''          function( byref x as T, byref y as T ) as boolean
''              return x < y
''          end function
''
''  The first FUNCTION there is a TYPE and opens nothing; the second is a body
''  and does. What separates them is position -- after `=`, `,` or `(` -- and
''  the shape of what follows: a parameter list, optionally a return type, and
''  then the end of the statement, because the body starts on the next line.
''  `cast( function( ) as long, p )` fails that second test on the comma, which
''  is exactly the false positive it is there to prevent.
'' ----------------------------------------------------------------------------
private function IsLambdaHeader( byref text_ as string, byref tokens as TokenArray, _
                                 byref stmt as FB.Array( of long ), byval at_ as long ) as boolean
    if( at_ + 1 >= stmt.Count( ) ) then return false

    dim as long paramAt = at_ + 1

    '' An optional CALLING CONVENTION comes first:
    ''     function cdecl( byval p1 as any ptr ) as long
    while( paramAt < stmt.Count( ) )
        dim as Token t = tokens[ stmt[paramAt] ]
        if( t.Kind = TK_KEYWORD andalso t.Kw = KW_OTHER ) then
            paramAt += 1
        else
            exit while
        end if
    wend
    if( paramAt >= stmt.Count( ) ) then return false

    '' Then an optional CAPTURE LIST: sub[ byref total ]( ... ).
    if( tokens[ stmt[paramAt] ].Kind = TK_LBRACKET ) then
        dim as long bdepth = 0
        while( paramAt < stmt.Count( ) )
            select case tokens[ stmt[paramAt] ].Kind
                case TK_LBRACKET : bdepth += 1
                case TK_RBRACKET
                    bdepth -= 1
                    if( bdepth = 0 ) then exit while
            end select
            paramAt += 1
        wend
        if( bdepth <> 0 ) then return false
        paramAt += 1
        if( paramAt >= stmt.Count( ) ) then return false
    end if

    if( tokens[ stmt[paramAt] ].Kind <> TK_LPAREN ) then return false

    '' Walk to the parameter list's closing parenthesis.
    dim as long depth = 0
    dim as long k = paramAt
    while( k < stmt.Count( ) )
        select case tokens[ stmt[k] ].Kind
            case TK_LPAREN : depth += 1
            case TK_RPAREN
                depth -= 1
                if( depth = 0 ) then exit while
        end select
        k += 1
    wend
    if( depth <> 0 ) then return false

    '' What follows must be nothing, or a RETURN TYPE and then nothing --
    '' because a lambda's body starts on the next line. The type may be
    ''
    ''     as boolean
    ''     byref as long
    ''     as function( byval x as long ) as long        <- parens of its own
    ''
    '' so keywords, names, dots and BALANCED parentheses are allowed. A comma
    '' or a closing parenthesis at the top level is not: those belong to an
    '' enclosing call, which is what makes `cast( function( ) as long, p )` a
    '' cast rather than a lambda.
    k += 1
    dim as long tailDepth = 0

    for j as long = k to stmt.Count( ) - 1
        dim as Token t = tokens[ stmt[j] ]
        select case t.Kind
            case TK_KEYWORD, TK_IDENT
                '' part of the type
            case TK_LPAREN, TK_LBRACKET
                tailDepth += 1
            case TK_RPAREN, TK_RBRACKET
                if( tailDepth = 0 ) then return false
                tailDepth -= 1
            case TK_COMMA
                if( tailDepth = 0 ) then return false
            case TK_OP
                if( TokenText( text_, t ) <> "." ) then return false
            case else
                return false
        end select
    next

    return tailDepth = 0
end function

'' ----------------------------------------------------------------------------
''  The statement walker
'' ----------------------------------------------------------------------------
sub ParseTokens( byref text_ as string, byref tokens as TokenArray, byref diags as DiagnosticArray )
    dim as ParseState st

    dim as long total = tokens.Count( )
    dim as long i = 0

    while( i < total )
        '' -- collect one statement -------------------------------------------
        ''
        '' A statement ends at the end of a logical line or at a colon. The
        '' lexer has already joined underscore-continued lines, and comments
        '' are dropped here so `if x then ' note` still ends with THEN.
        dim stmt as FB.Array( of long )
        dim as long parenDepth = 0
        dim as long openParenAt = -1
        dim as boolean done_ = false

        '' A directive runs to the end of its logical line, colons included: a
        '' colon inside a macro body separates statements of the EXPANSION, not
        '' of this file. fb/comptr.bi defines a macro whose body is
        '' `private function ... : return ... : end function`, and splitting on
        '' those colons left an `end function` with nothing to close.
        dim as boolean ppStatement = false
        if( i < total ) then ppStatement = ( tokens[i].Kind = TK_PP )

        while( i < total andalso done_ = false )
            dim as Token t = tokens[i]

            select case t.Kind
                case TK_EOF
                    '' Consumed, not just noted: leaving `i` on the EOF token
                    '' means the outer loop never sees i >= total and spins
                    '' forever on a document whose last statement is empty.
                    i = total
                    done_ = true

                case TK_EOL
                    i += 1
                    done_ = true

                case TK_COLON
                    '' Only a separator at the top level: a colon inside
                    '' parentheses belongs to whatever is being written there,
                    '' and one inside a directive belongs to its expansion.
                    if( parenDepth = 0 andalso ppStatement = false ) then
                        i += 1
                        done_ = true
                    else
                        i += 1
                    end if

                case TK_COMMENT
                    i += 1

                case TK_LPAREN, TK_LBRACKET
                    if( parenDepth = 0 ) then openParenAt = t.Start_
                    parenDepth += 1
                    stmt.Push( i )
                    i += 1

                case TK_RPAREN, TK_RBRACKET
                    if( parenDepth = 0 ) then
                        if( st.Pending_ > 0 ) then
                            '' Closing a call that wrapped a lambda body.
                            st.Pending_ -= 1
                        else
                            Report( st, diags, t.Start_, t.Start_ + t.Length_, _
                                    DIAGCODE_UNBALANCED_PAREN, _
                                    "unmatched '" & TokenText( text_, t ) & "'" )
                        end if
                    else
                        parenDepth -= 1
                    end if
                    stmt.Push( i )
                    i += 1

                case else
                    stmt.Push( i )
                    i += 1
            end select
        wend

        '' The report waits until the statement has been classified: a
        '' statement that opens a lambda is ALLOWED to end with parentheses
        '' still open.
        dim as long unclosedParens = parenDepth
        dim as long unclosedAt     = openParenAt

        if( stmt.Count( ) = 0 ) then
            if( i >= total ) then exit while
            continue while
        end if

        '' -- what kind of statement is it? -------------------------------------
        dim as long first_ = 0

        '' Leading modifiers only qualify what follows: `private virtual
        '' destructor Renderer( )` is a destructor body, and
        '' `private const function DirEntry.Name( )` is a function body. Missing
        '' either made its `end ...` look orphaned.
        while( first_ < stmt.Count( ) )
            dim as Token m = tokens[ stmt[first_] ]
            if( m.Kind <> TK_KEYWORD ) then exit while
            select case m.Kw
                case KW_PRIVATE, KW_PUBLIC, KW_PROTECTED, KW_STATIC, KW_VIRTUAL, _
                     KW_ABSTRACT, KW_CONST
                    first_ += 1
                case else
                    exit while
            end select
        wend

        if( first_ >= stmt.Count( ) ) then
            if( i >= total ) then exit while
            continue while
        end if

        dim as long   headIdx = stmt[first_]
        dim as Token  head    = tokens[ headIdx ]
        dim as long   lastIdx = stmt[ stmt.Count( ) - 1 ]

        '' -- preprocessor -------------------------------------------------------
        if( head.Kind = TK_PP ) then
            dim as long ppTop = st.PpStack_.Count( ) - 1

            select case head.Kw
                case KW_PP_IF, KW_PP_IFDEF, KW_PP_IFNDEF
                    PushPp( st, KW_PP_IF, "", head )

                case KW_PP_MACRO
                    dim as string name_ = ""
                    if( first_ + 1 < stmt.Count( ) ) then
                        name_ = ReadName( text_, tokens, stmt[first_ + 1], lastIdx )
                    end if
                    PushPp( st, KW_PP_MACRO, name_, head )

                case KW_PP_ELSE, KW_PP_ELSEIF
                    dim as string clause = iif( head.Kw = KW_PP_ELSE, "#else", "#elseif" )
                    if( ppTop < 0 orelse st.PpStack_[ppTop].Kind_ <> KW_PP_IF ) then
                        Report( st, diags, head.Start_, head.Start_ + head.Length_, _
                                DIAGCODE_ORPHAN_CLAUSE, "'" & clause & "' outside a '#if' block" )
                    else
                        '' Whatever the branch just left behind opened, it is
                        '' not this branch's business.
                        DropBlocksTo( st, st.PpStack_[ppTop].DepthAtOpen )
                    end if

                case KW_PP_ENDIF
                    if( ppTop < 0 orelse st.PpStack_[ppTop].Kind_ <> KW_PP_IF ) then
                        Report( st, diags, head.Start_, head.Start_ + head.Length_, _
                                DIAGCODE_UNEXPECTED_END, "'#endif' has no matching '#if'" )
                    else
                        '' Blocks the surviving branch opened stay open: they
                        '' are routinely closed after the #endif.
                        st.PpStack_.Pop( )
                    end if

                case KW_DEFINE
                    '' `#define NAME extern "C"` and friends. A parameterised
                    '' macro -- NAME( a, b ) -- is skipped: it is called in an
                    '' expression, not written on a line by itself.
                    if( first_ + 2 < stmt.Count( ) ) then
                        dim as Token nameTok = tokens[ stmt[first_ + 1] ]
                        dim as Token bodyTok = tokens[ stmt[first_ + 2] ]

                        if( nameTok.Kind = TK_IDENT andalso bodyTok.Kind = TK_KEYWORD ) then
                            dim as boolean opens = false
                            select case bodyTok.Kw
                                case KW_TYPE, KW_UNION, KW_ENUM, KW_NAMESPACE, _
                                     KW_SCOPE, KW_WITH, KW_ASM
                                    opens = true
                                case KW_EXTERN
                                    '' Same rule as a written-out EXTERN: only
                                    '' `extern "C"` opens anything.
                                    if( first_ + 3 < stmt.Count( ) ) then
                                        opens = ( tokens[ stmt[first_ + 3] ].Kind = TK_STRING )
                                    end if
                            end select

                            if( opens ) then
                                dim as MacroOpener m
                                m.Name_ = lcase( TokenText( text_, nameTok ) )
                                m.Kind_ = bodyTok.Kw
                                st.Macros_.Push( m )
                            end if
                        end if
                    end if

                case KW_PP_ENDMACRO
                    if( ppTop < 0 orelse st.PpStack_[ppTop].Kind_ <> KW_PP_MACRO ) then
                        Report( st, diags, head.Start_, head.Start_ + head.Length_, _
                                DIAGCODE_UNEXPECTED_END, "'#endmacro' has no matching '#macro'" )
                    else
                        '' A macro body is text, and half of one is legal.
                        DropBlocksTo( st, st.PpStack_[ppTop].DepthAtOpen )
                        st.PpStack_.Pop( )
                    end if
            end select

            if( i >= total ) then exit while
            continue while
        end if

        '' A bare identifier on a line of its own may be a macro that expands
        '' to a block opener.
        if( head.Kind = TK_IDENT andalso stmt.Count( ) = first_ + 1 ) then
            dim as FbKeyword macroKind = MacroOpenerKind( st, TokenText( text_, head ) )
            if( macroKind <> KW_NONE ) then PushBlock( st, macroKind, "", head )
        end if

        '' -- keyword-headed statements -------------------------------------------
        ''
        '' A statement headed by anything else falls THROUGH to the lambda scan
        '' below rather than returning here: `SortBy( a, function( ... )` is
        '' headed by an identifier and still opens a block.
        dim as FbKeyword nextKw = KW_NONE
        dim as Token     nextTok
        dim as boolean   hasNext = (first_ + 1 < stmt.Count( ))
        if( hasNext ) then
            nextTok = tokens[ stmt[first_ + 1] ]
            if( nextTok.Kind = TK_KEYWORD ) then nextKw = nextTok.Kw
        end if

        if( head.Kind <> TK_KEYWORD ) then head.Kw = KW_NONE

        select case head.Kw
            '' -- things that look like openers but are not ---------------------
            case KW_DECLARE, KW_EXIT, KW_CONTINUE
                '' `declare sub Foo` opens nothing; `exit sub` and
                '' `continue for` close nothing.

            '' -- closers --------------------------------------------------------
            case KW_END
                '' `end` alone, or `end 1`, is the END STATEMENT and closes
                '' nothing. Only `end <block-keyword>` is a closer.
                if( hasNext andalso nextKw <> KW_NONE ) then
                    select case nextKw
                        case KW_SUB, KW_FUNCTION, KW_PROPERTY, KW_CONSTRUCTOR, _
                             KW_DESTRUCTOR, KW_OPERATOR, KW_TYPE, KW_UNION, _
                             KW_ENUM, KW_NAMESPACE, KW_SCOPE, KW_WITH, _
                             KW_EXTERN, KW_ASM, KW_IF, KW_SELECT
                            CloseBlock( st, diags, nextKw, head, "end " & BlockWord( nextKw ) )
                    end select
                end if

            case KW_ENDIF
                CloseBlock( st, diags, KW_IF, head, "endif" )

            case KW_WEND
                CloseBlock( st, diags, KW_WHILE, head, "wend" )

            case KW_LOOP
                CloseBlock( st, diags, KW_DO, head, "loop" )

            case KW_NEXT
                '' `next i, j` closes two loops: one per name, and one for the
                '' bare form.
                dim as long closes = 1
                for k as long = first_ + 1 to stmt.Count( ) - 1
                    if( tokens[ stmt[k] ].Kind = TK_COMMA ) then closes += 1
                next
                for k as long = 1 to closes
                    CloseBlock( st, diags, KW_FOR, head, "next" )
                next

            '' -- clauses that must be inside something ---------------------------
            case KW_ELSE
                RequireInside( st, diags, KW_IF, head, "else" )
            case KW_ELSEIF
                RequireInside( st, diags, KW_IF, head, "elseif" )
            case KW_CASE
                RequireInside( st, diags, KW_SELECT, head, "case" )

            '' -- procedure bodies -------------------------------------------------
            case KW_SUB, KW_FUNCTION, KW_PROPERTY, KW_CONSTRUCTOR, KW_DESTRUCTOR, KW_OPERATOR
                '' `function = expr`, `property = expr` and `operator = expr`
                '' all SET THE RESULT of the procedure they are inside. None of
                '' them opens anything.
                ''
                '' The awkward one is OPERATOR, because `operator =` is also how
                '' the equality operator is DEFINED:
                ''
                ''     operator = ( byref a as V, byref b as V ) as boolean   <- opens
                ''     operator = ( ( a.x = b.x ) = false )                   <- assigns
                ''
                '' A definition states a return type, so a top-level AS is what
                '' tells them apart. Both spellings appear in fb/vector.bi.
                dim as boolean isResultAssign = false
                if( hasNext ) then
                    select case head.Kw
                        case KW_CONSTRUCTOR
                            '' `constructor( 5 )` inside a constructor body
                            '' CHAINS to another overload. A definition always
                            '' names its type -- `constructor T( )` -- because
                            '' the in-type form is a DECLARE.
                            isResultAssign = ( nextTok.Kind = TK_LPAREN )

                        case KW_FUNCTION, KW_PROPERTY, KW_OPERATOR
                            if( nextTok.Kind = TK_OP andalso TokenText( text_, nextTok ) = "=" ) then
                                isResultAssign = true

                                dim as long depth = 0
                                for k as long = first_ + 1 to stmt.Count( ) - 1
                                    dim as Token t = tokens[ stmt[k] ]
                                    select case t.Kind
                                        case TK_LPAREN, TK_LBRACKET : depth += 1
                                        case TK_RPAREN, TK_RBRACKET : depth -= 1
                                        case TK_KEYWORD
                                            if( t.Kw = KW_AS andalso depth = 0 ) then
                                                isResultAssign = false
                                                exit for
                                            end if
                                    end select
                                next
                            end if
                    end select
                end if

                if( isResultAssign = false ) then
                    dim as string name_ = ""
                    if( hasNext ) then name_ = ReadName( text_, tokens, stmt[first_ + 1], lastIdx )
                    PushBlock( st, head.Kw, name_, head )
                end if

            '' -- type-ish blocks ---------------------------------------------------
            case KW_TYPE
                '' Three spellings share the word:
                ''     type Foo            a block
                ''     type Foo as Bar     an ALIAS, and no block
                ''     type<Foo>( ... )    a temporary, in an expression
                dim as boolean isBlock = false

                '' A bare TYPE on its own line is an ANONYMOUS NESTED type,
                '' which fbc's own ir-gas64.bas uses inside a union:
                ''     union ustab
                ''         full as longint
                ''         type
                ''             offst as long
                ''         end type
                ''     end union
                if( hasNext = false ) then isBlock = true

                '' The name may lex as a KEYWORD inside a macro body, where a
                '' parameter shadows one: fbc's objinfo.bas writes
                '' `#macro DEFINE_SEGMENT_COMMAND(NAME, SIZE_TYPE)` and then
                '' `type NAME`, and NAME is the reserved word for the NAME
                '' statement. Either way, an `end type` is coming.
                dim as boolean namedNext = false
                if( hasNext ) then
                    if( nextTok.Kind = TK_IDENT ) then
                        namedNext = true
                    elseif( nextTok.Kind = TK_KEYWORD andalso nextTok.Kw <> KW_AS ) then
                        namedNext = true
                    end if
                end if

                if( namedNext ) then
                    isBlock = true
                    for k as long = first_ + 1 to stmt.Count( ) - 1
                        dim as Token t = tokens[ stmt[k] ]
                        if( t.Kind = TK_KEYWORD andalso t.Kw = KW_AS ) then
                            isBlock = false
                            exit for
                        end if
                    next
                end if

                if( isBlock ) then
                    PushBlock( st, KW_TYPE, ReadName( text_, tokens, stmt[first_ + 1], lastIdx ), head )
                end if

            case KW_UNION, KW_ENUM, KW_NAMESPACE
                if( HasTopLevelAs( tokens, stmt, first_ + 1 ) = false ) then
                    dim as string name_ = ""
                    if( hasNext ) then name_ = ReadName( text_, tokens, stmt[first_ + 1], lastIdx )
                    PushBlock( st, head.Kw, name_, head )
                end if

            case KW_FOR
                '' FOR is exempt from the field test: `for i as long = 0 to 9`
                '' has a top-level AS of its own.
                PushBlock( st, KW_FOR, "", head )

            case KW_SELECT
                '' FreeBASIC spells it `select case expr`. Without the CASE
                '' this is a field or a variable that happens to be named
                '' `select`.
                if( nextKw = KW_CASE ) then PushBlock( st, KW_SELECT, "", head )

            case KW_SCOPE, KW_WITH, KW_ASM, KW_WHILE, KW_DO
                if( HasTopLevelAs( tokens, stmt, first_ + 1 ) = false ) then
                    PushBlock( st, head.Kw, "", head )
                end if

            case KW_EXTERN
                '' `extern "C"` opens a block; `extern x as long` declares.
                if( hasNext andalso nextTok.Kind = TK_STRING ) then
                    PushBlock( st, KW_EXTERN, "", head )
                end if

            case KW_IF
                '' A block IF is one whose THEN is the last thing on the line.
                '' `if x then y = 1` is a whole statement and opens nothing.
                dim as Token lastTok = tokens[ lastIdx ]
                if( lastTok.Kind = TK_KEYWORD andalso lastTok.Kw = KW_THEN ) then
                    PushBlock( st, KW_IF, "", head )
                end if
        end select

        '' -- lambdas, which open a block from inside an expression -------------
        dim as boolean openedLambda = false
        for k as long = first_ + 1 to stmt.Count( ) - 1
            dim as Token t = tokens[ stmt[k] ]
            if( t.Kind <> TK_KEYWORD ) then continue for
            if( t.Kw <> KW_FUNCTION andalso t.Kw <> KW_SUB ) then continue for

            '' Expression position: after `=`, `,`, `(`, or an ordinary
            '' keyword such as RETURN. NOT after a structural one -- `as
            '' function( ... )` is a TYPE, `declare function` is a prototype,
            '' and `end function` is a terminator.
            dim as Token prev_ = tokens[ stmt[k - 1] ]
            dim as boolean inExpression = false
            select case prev_.Kind
                case TK_COMMA, TK_LPAREN : inExpression = true
                case TK_OP               : inExpression = ( TokenText( text_, prev_ ) = "=" )
                case TK_KEYWORD          : inExpression = ( prev_.Kw = KW_OTHER )
            end select

            if( inExpression andalso IsLambdaHeader( text_, tokens, stmt, k ) ) then
                PushBlock( st, t.Kw, "", t )
                openedLambda = true
            end if
        next

        if( unclosedParens > 0 andalso unclosedAt >= 0 ) then
            if( openedLambda ) then
                st.Pending_ += unclosedParens
            else
                Report( st, diags, unclosedAt, unclosedAt + 1, _
                        DIAGCODE_UNBALANCED_PAREN, _
                        "unmatched '(' -- the statement ends before it is closed" )
            end if
        end if

        if( i >= total ) then exit while
    wend

    '' -- anything still open at the end of the file ---------------------------
    for k as long = 0 to st.PpStack_.Count( ) - 1
        dim as PpFrame frame = st.PpStack_[k]
        Report( st, diags, frame.StartOffset, frame.EndOffset, _
                DIAGCODE_UNCLOSED_BLOCK, _
                "'" & BlockWord( frame.Kind_ ) & "' is never closed -- expected '" & _
                CloserWord( frame.Kind_ ) & "'" )
    next

    for k as long = 0 to st.Stack_.Count( ) - 1
        dim as BlockFrame frame = st.Stack_[k]
        Report( st, diags, frame.StartOffset, frame.EndOffset, _
                DIAGCODE_UNCLOSED_BLOCK, _
                DescribeFrame( frame ) & " is never closed -- expected '" & _
                CloserWord( frame.Kind_ ) & "'" )
    next
end sub

sub AnalyzeSource( byref text_ as string, byref diags as DiagnosticArray )
    diags.Clear( )

    '' A UTF-16 source -- which fbc accepts, and which its own
    '' tests/string/asc-utf16le.bas is -- is not something this byte-oriented
    '' lexer can read. Reporting two thousand "unexpected character" errors
    '' would be worse than reporting none, so it says nothing at all.
    if( len(text_) >= 2 ) then
        dim as ubyte b0 = text_[0], b1 = text_[1]
        if( (b0 = &hFF andalso b1 = &hFE) orelse (b0 = &hFE andalso b1 = &hFF) ) then exit sub
    end if

    dim as TokenArray tokens
    LexSource( text_, tokens, diags )
    ParseTokens( text_, tokens, diags )
end sub
