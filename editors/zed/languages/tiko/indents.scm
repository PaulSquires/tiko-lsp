; tiko-tree-sitter -- indentation
;
; Every block indents its body by one level and outdents on its closer. The
; closers are single tokens (`end sub`, not `end` + `sub`), so @outdent lands
; on the whole word pair and re-indenting the line while it is still being
; typed does not fight the parser.

[
  (procedure_definition)
  (type_definition)
  (union_definition)
  (enum_definition)
  (namespace_definition)
  (extern_block)
  (scope_block)
  (with_block)
  (asm_block)
  (if_statement)
  (elseif_clause)
  (else_clause)
  (select_statement)
  (case_clause)
  (for_statement)
  (while_statement)
  (do_statement)
  (preproc_macro)
  (parameter_list)
] @indent

[
  "end sub" "end function" "end property" "end constructor"
  "end destructor" "end operator"
  "end type" "end union" "end enum" "end namespace" "end extern"
  "end scope" "end with" "end select" "end asm" "end if" "end while"
  "endif" "wend" "loop" "next"
  "else" "elseif" "case"
  "#endmacro"
  ")" "]" "}"
] @outdent
