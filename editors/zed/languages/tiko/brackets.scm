; tree-sitter-tiko -- bracket matching
;
; The block openers are matched to their closers as well as the punctuation,
; so jump-to-match works on `sub`/`end sub` the way it does on `(`/`)`.

("(" @open ")" @close)
("[" @open "]" @close)
("{" @open "}" @close)

; The opener is the procedure word, not the name that follows it -- `. (_)`
; would anchor on whichever child came first, and for a `private sub` that is
; the modifier.
(procedure_definition
  kind: _ @open
  close: _ @close)
(type_definition       "type"      @open "end type"      @close)
(union_definition      "union"     @open "end union"     @close)
(namespace_definition  "namespace" @open "end namespace" @close)
(extern_block          "extern"    @open "end extern"    @close)
(scope_block           "scope"     @open "end scope"     @close)
(with_block            "with"      @open "end with"      @close)
(asm_block             "asm"       @open "end asm"       @close)
(select_statement      "select"    @open "end select"    @close)

; ZED WILL NOT TAKE A FIELD OR A KEYWORD INSIDE `enum_definition`.
; `(enum_definition name: ...)` and `(enum_definition "enum" ...)` are both
; rejected -- silently: the language then never attaches, so the file loses
; highlighting AND the language server, with nothing in the log to say why.
; A NAMED child is accepted, which is why the enum is matched through its
; `(identifier)` instead.
