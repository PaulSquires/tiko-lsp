; tiko-tree-sitter -- highlights
;
; TWO SOURCES OF COLOUR, and the split is deliberate.
;
;   * The grammar knows the STRUCTURAL words -- `sub`, `end sub`, `if`, `for`,
;     `namespace` -- because they delimit blocks, so they are matched here as
;     ordinary anonymous nodes.
;
;   * Every other reserved word -- `print`, `mod`, `sizeof`, `andalso`, the
;     two hundred of them -- is an `identifier` to the grammar and is coloured
;     by the `#match?` list at the bottom of this file. tiko is
;     CASE-INSENSITIVE, so the pattern carries both cases of every letter
;     class; `#match?` is a regex match, not a set lookup, which is why the
;     list is written as one alternation rather than two hundred patterns.
;
; Rules later in the file win, so the specific captures (a call, a type, a
; declaration name) come AFTER the blanket keyword match.

; --------------------------------------------------------------- literals

(comment) @comment
(string) @string
(number) @number
(operator) @operator

[ "(" ")" "[" "]" "{" "}" ] @punctuation.bracket
[ "," "." ":" ] @punctuation.delimiter
"..." @punctuation.special

; ------------------------------------------------------- structural words

[
  "sub" "function" "property" "constructor" "destructor" "operator"
  "declare"
  "type" "union" "enum" "namespace" "extern" "scope" "with" "asm"
  "if" "then" "else" "elseif" "endif"
  "select" "case" "is"
  "for" "next" "while" "wend" "do" "loop" "until"
  "exit" "continue" "end"
  "as" "of" "extends" "field" "explicit" "once"
  "channel" "link"
  "class" "interface" "inherits" "implements"
] @keyword

[
  "end sub" "end function" "end property" "end constructor"
  "end destructor" "end operator"
  "end type" "end union" "end enum" "end namespace" "end extern"
  "end scope" "end with" "end select" "end asm" "end if" "end while"
  "end class" "end interface"
] @keyword

(end_statement) @keyword
(exit_statement) @keyword.control

[
  "private" "public" "protected" "static" "shared"
  "const" "virtual" "abstract" "byref" "byval"
] @keyword.modifier

(modifier) @keyword.modifier
(access_specifier) @keyword.modifier

; ------------------------------------------------------------ preprocessor

(preproc_directive) @keyword.directive
[ "#include" "#module" "#import" "#export" "#define" "#macro" "#endmacro" ] @keyword.directive
(preproc_include path: (string) @string.special.path)
(preproc_import path: (string) @string.special.path)
(preproc_import alias: (identifier) @module)
(preproc_module name: (string) @module)
(preproc_export name: (identifier) @constant.macro)
(preproc_define name: (identifier) @constant.macro)
(preproc_macro name: (identifier) @function.macro)
(macro_text) @none
(asm_text) @none
(open_text) @none

; ------------------------------------------------------------ declarations

(procedure_definition
  name: (qualified_name (identifier) @function))
(declare_statement
  name: (qualified_name (identifier) @function))

(type_definition name: (identifier) @type)
; A field or keyword inside `union_definition` costs ~50s of query analysis
; against this grammar (5,497 parse states); the named-child form takes 0.3s.
(union_definition (identifier) @type)
(enum_definition name: (identifier) @type)
(type_alias name: (identifier) @type)
; CLASS AND INTERFACE are matched through the named child, as union and enum
; are: no field or keyword inside either definition. A class's `extends` base
; is a direct identifier too, and is a type as well.
(class_definition (identifier) @type)
(interface_definition (identifier) @type)
(interface_method (qualified_name (identifier) @function))
(inherits_clause (qualified_name (identifier) @type))
(implements_clause (qualified_name (identifier) @type))
(namespace_definition name: (qualified_name (identifier) @module))
(generic_parameters (identifier) @type.parameter)

(enum_member name: (identifier) @constant)
(keyword_field name: (identifier) @variable.member)
(parameter name: (identifier) @variable.parameter)
(label name: (identifier) @label)
(for_statement variable: (identifier) @variable)

; ------------------------------------------------------------------- uses

; `Foo( ... )` -- a call, an array index or a cast. The grammar does not know
; which, and neither does any editor colour scheme; all three read as a call.
((identifier) @function.call . "(")

; ------------------------------------------------------- the word list
;
; Everything the grammar leaves as an identifier but the language reserves.
; Kept in the same order as the server's own table so the two can be diffed.

((identifier) @keyword
  (#match? @keyword
   "^(?i)(abs|abstract|access|acos|alias|and|andalso|any|append|as|asc|asin|atan2|atn|base|binary|boolean|byte|call|cast|cbool|cbyte|cdbl|cdecl|chr|cint|circle|class|clng|clngint|close|color|common|cos|cptr|cshort|csign|csng|cubyte|cuint|culng|culngint|cunsg|cushort|cva_arg|cva_copy|cva_end|cva_start|cvd|cvi|cvl|cvlongint|cvs|cvshort|data|defbyte|defdbl|defined|defint|deflng|deflongint|defshort|defsng|defstr|defubyte|defuint|defulng|defulongint|defushort|delete|dim|double|draw|dynamic|encoding|eqv|erase|err|error|exp|export|fix|frac|get|gosub|goto|iif|imagecreate|imp|implements|import|include|input|instr|instrrev|int|integer|lbound|lcase|len|let|lib|line|local|lock|log|long|longint|lprint|lset|ltrim|mid|mkd|mki|mkl|mklongint|mks|mkshort|mod|name|new|not|on|open|option|or|orelse|output|overload|paint|palette|pascal|peek|point|pointer|poke|preserve|preset|print|procptr|pset|ptr|put|random|read|redim|rem|restore|resume|return|rset|rtrim|sadd|screen|seek|sgn|shl|short|shr|sin|single|sizeof|spc|sqr|stdcall|step|str|string|strptr|swap|tab|tan|then|threadcall|to|trim|typeof|ubound|ubyte|ucase|uinteger|ulong|ulongint|unlock|unsigned|ushort|using|ustring|var|varptr|va_first|view|virtual|wchr|width|window|winput|write|wstr|wstring|xor|zstring|__fastcall|__thiscall)$"))

; The built-in TYPE names, coloured as types rather than as plain keywords.
((identifier) @type.builtin
  (#match? @type.builtin
   "^(?i)(any|boolean|byte|double|integer|long|longint|short|single|string|ustring|ubyte|uinteger|ulong|ulongint|ushort|wstring|zstring|ptr|pointer|int8|uint8|int16|uint16|int32|uint32|int64|uint64|float32|float64)$"))

; tiko-lang's predeclared constant, `const nullptr as any ptr = 0`. Not a
; keyword -- a program may declare its own, which the grammar cannot see --
; so it is matched here as the fixed-width type names above are.
((identifier) @constant.builtin
  (#match? @constant.builtin "^(?i)(nullptr)$"))
