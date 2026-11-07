; tiko-tree-sitter -- outline / symbol list
;
; What belongs in an outline is what a reader navigates by: procedures, the
; user-defined types, the namespaces around them, and the macros -- because in
; this language a macro is often the interface.

(procedure_definition
  kind: _ @context
  name: (qualified_name) @name) @item

(declare_statement
  kind: _ @context
  name: (qualified_name) @name) @item

(type_definition  "type"      @context name: (identifier) @name) @item
; UNION, TOO: a field or keyword inside `union_definition` costs ~50s of
; query analysis against this grammar (5,497 parse states), and Zed starts
; the language server only after every query has compiled. Match the name
; through the named child; it compiles in 0.3s.
(union_definition (identifier) @name) @item
; ZED WILL NOT TAKE A FIELD OR A KEYWORD INSIDE `enum_definition`.
; `(enum_definition name: ...)` and `(enum_definition "enum" ...)` are both
; rejected -- silently: the language then never attaches, so the file loses
; highlighting AND the language server, with nothing in the log to say why.
; A NAMED child is accepted, which is why the enum is matched through its
; `(identifier)` instead.
(enum_definition (identifier) @name) @item
; Named children only, as for union and enum (see highlights.scm).
(class_definition (identifier) @name) @item
(interface_definition (identifier) @name) @item
(interface_method (qualified_name) @name) @item
(namespace_definition "namespace" @context name: (qualified_name) @name) @item
(type_alias       "type"      @context name: (identifier) @name) @item

(preproc_module "#module" @context name: (string) @name) @item
(preproc_import "#import" @context path: (string) @name) @item
(preproc_macro  "#macro"  @context name: (identifier) @name) @item
(preproc_define "#define" @context name: (identifier) @name) @item
