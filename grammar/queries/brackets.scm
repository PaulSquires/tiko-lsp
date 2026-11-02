; tiko-tree-sitter -- bracket matching
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
; A field or keyword inside `union_definition` costs ~50s of query analysis
; against this grammar (5,497 parse states); the named-child form takes 0.3s.
; There is no named child to hang a bracket pair on, so the pair is dropped.
(enum_definition       "enum"      @open "end enum"      @close)
(namespace_definition  "namespace" @open "end namespace" @close)
(extern_block          "extern"    @open "end extern"    @close)
(scope_block           "scope"     @open "end scope"     @close)
(with_block            "with"      @open "end with"      @close)
(asm_block             "asm"       @open "end asm"       @close)
(select_statement      "select"    @open "end select"    @close)
