'' ############################################################################
''  analysis/format.bi -- re-indenting a document
''
''  WHAT IT CHANGES: leading whitespace, trailing whitespace, and the final
''  newline. That is the whole list.
''
''  WHAT IT DOES NOT CHANGE, and why: everything else a formatter could do to
''  FreeBASIC is a matter of taste that the language does not settle. Keyword
''  case (`Sub` or `sub`), space inside parentheses, alignment of consecutive
''  assignments, whether a `_` continuation lines up under its opener -- there
''  is no compiler rule to appeal to, and a formatter that rewrites a file to
''  ITS taste on every save is one the user turns off. Indentation is the one
''  thing that has a right answer, because it is the block structure, and this
''  server already computes that.
''
''  IT REFUSES ON BROKEN CODE. If the parser reported an error -- an unclosed
''  SUB, an `end if` with no `if` -- the block structure is not known, and
''  re-indenting from a wrong structure moves a screenful of lines to the wrong
''  column. Doing nothing and saying so is the only honest answer, and it is
''  the difference between a formatter that is safe on format-on-save and one
''  that is not.
''
''  Lines inside a multi-line comment and inside a #macro body are left
''  untouched: comment art is not indentation, and a macro body is text.
'' ############################################################################

#pragma once

#include once "fb/array.bi"
#include once "parser.bi"
#include once "../utils/position.bi"

'' The subset of LSP's FormattingOptions that means something here. The
'' defaults are the protocol's own: four spaces, no tab.
type FormatOptions
    TabSize                as long
    InsertSpaces           as boolean
    TrimTrailingWhitespace as boolean
    InsertFinalNewline     as boolean
    TrimFinalNewlines      as boolean
end type

declare function DefaultFormatOptions( ) as FormatOptions

'' One edit, in LSP coordinates, ready to become a TextEdit.
type TextEditRec
    StartLine as long
    StartChar as long
    EndLine   as long
    EndChar   as long
    NewText   as string
end type

type TextEditArray as FB.Array( of TextEditRec )

'' The edits that re-indent lines [firstLine, lastLine] of `text_`.
''
'' The structure is computed from the WHOLE document even when only a range is
'' being formatted -- a range knows nothing about how deep it is nested. Pass
'' firstLine = 0 and lastLine = -1 for the whole file.
''
'' Returns FALSE and produces no edits when the document has structural errors.
'' `reason` says which, so a caller can log it or tell the user.
declare function ComputeFormatEdits( byref text_ as string, byref idx as LineIndex, _
                                     byref opts as FormatOptions, _
                                     byval firstLine as long, byval lastLine as long, _
                                     byref edits as TextEditArray, _
                                     byref reason as string ) as boolean

'' Applies edits to text, for tests and for anything that wants the result
'' rather than the edits. The edits must be non-overlapping and in order,
'' which is what ComputeFormatEdits produces.
declare function ApplyTextEdits( byref text_ as string, byref idx as LineIndex, _
                                 byref edits as TextEditArray ) as string
