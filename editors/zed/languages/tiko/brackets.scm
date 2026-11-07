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
; UNION, TOO: a field or keyword inside `union_definition` costs ~50s of
; query analysis against this grammar (5,497 parse states), and Zed starts
; the language server only after every query has compiled. There is no
; named child to hang a bracket pair on, so the pair is dropped.
(interface_definition  "interface" @open "end interface" @close)
; No pair for CLASS: like a union's, a keyword inside `class_definition` costs
; ~4.5s of query analysis on its own (it shares the type body's states).
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
