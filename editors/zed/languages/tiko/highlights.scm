; Tiko -- highlights, for Zed.
;
; The same queries as the grammar's own, with the captures mapped onto the set
; Zed's themes actually colour: no `keyword.modifier`, no `type.parameter`, no
; `module` -- a capture a theme does not know is simply not painted, which is
; indistinguishable from a broken query.
;
; TWO SOURCES OF COLOUR. The grammar knows the STRUCTURAL words, because they
; delimit blocks. Every other reserved word -- `print`, `mod`, `sizeof`, the
; two hundred of them -- is an `identifier` to the parser and is coloured by
; the `#match?` list at the bottom of this file. Rules later in the file win,
; so the specific captures come after the blanket one.

(comment) @comment
(string) @string
(number) @number
(operator) @operator

[ "(" ")" "[" "]" "{" "}" ] @punctuation.bracket
[ "," "." ":" ] @punctuation.delimiter
"..." @punctuation.special

[
  "sub" "function" "property" "constructor" "destructor" "operator"
  "declare"
  "type" "union" "enum" "namespace" "extern" "scope" "with" "asm"
  "if" "then" "else" "elseif" "endif"
  "select" "case" "is"
  "for" "next" "while" "wend" "do" "loop" "until"
  "exit" "continue" "end"
  "as" "of" "extends" "field" "explicit" "once"
  "private" "public" "protected" "static" "shared"
  "const" "virtual" "abstract" "byref" "byval"
] @keyword

[
  "end sub" "end function" "end property" "end constructor"
  "end destructor" "end operator"
  "end type" "end union" "end enum" "end namespace" "end extern"
  "end scope" "end with" "end select" "end asm" "end if" "end while"
] @keyword

(end_statement) @keyword
(exit_statement) @keyword
(modifier) @keyword
(access_specifier) @keyword

(preproc_directive) @preproc
[ "#include" "#define" "#macro" "#endmacro" ] @preproc
(preproc_include path: (string) @string.special)
(preproc_define name: (identifier) @constant)
(preproc_macro name: (identifier) @function)

(procedure_definition name: (qualified_name (identifier) @function))
(declare_statement    name: (qualified_name (identifier) @function))
(lambda kind: _ @keyword)

(type_definition  name: (identifier) @type)
(union_definition name: (identifier) @type)
(enum_definition  name: (identifier) @type)
(type_alias       name: (identifier) @type)
(namespace_definition name: (qualified_name (identifier) @type))
(generic_parameters (identifier) @type)

(enum_member name: (identifier) @constant)
(bitfield    name: (identifier) @property)
(parameter   name: (identifier) @variable)
(label       name: (identifier) @label)
(for_statement variable: (identifier) @variable)
(member_access (identifier) @property)

; `Foo( ... )` -- a call, an array index or a cast. The grammar does not know
; which, and neither does any colour scheme; all three read as a call.
((identifier) @function . "(")

; Everything the grammar leaves as an identifier but the language reserves.
((identifier) @keyword
  (#match? @keyword
   "^(?i)(abs|abstract|access|acos|alias|and|andalso|any|append|as|asc|asin|atan2|atn|base|binary|boolean|byte|call|cast|cbool|cbyte|cdbl|cdecl|chr|cint|circle|class|clng|clngint|close|color|common|cos|cptr|cshort|csign|csng|cubyte|cuint|culng|culngint|cunsg|cushort|cva_arg|cva_copy|cva_end|cva_start|cvd|cvi|cvl|cvlongint|cvs|cvshort|data|defbyte|defdbl|defined|defint|deflng|deflongint|defshort|defsng|defstr|defubyte|defuint|defulng|defulongint|defushort|delete|dim|double|draw|dynamic|encoding|eqv|erase|err|error|exp|export|fix|frac|get|gosub|goto|iif|imagecreate|imp|implements|import|include|input|instr|instrrev|int|integer|lbound|lcase|len|let|lib|line|local|lock|log|long|longint|lprint|lset|ltrim|mid|mkd|mki|mkl|mklongint|mks|mkshort|mod|name|new|not|on|open|option|or|orelse|output|overload|paint|palette|pascal|peek|point|pointer|poke|preserve|preset|print|procptr|pset|ptr|put|random|read|redim|rem|restore|resume|return|rset|rtrim|sadd|screen|seek|sgn|shl|short|shr|sin|single|sizeof|spc|sqr|stdcall|step|str|string|strptr|swap|tab|tan|then|threadcall|to|trim|typeof|ubound|ubyte|ucase|uinteger|ulong|ulongint|unlock|unsigned|ushort|using|ustring|var|varptr|va_first|view|virtual|wchr|width|window|winput|write|wstr|wstring|xor|zstring|__fastcall|__thiscall)$"))

; The built-in TYPE names, coloured as types rather than as plain keywords.
((identifier) @type
  (#match? @type
   "^(?i)(any|boolean|byte|double|integer|long|longint|short|single|string|ubyte|uinteger|ulong|ulongint|ushort|wstring|zstring|ptr|pointer)$"))
