; tree-sitter-tiko -- outline / symbol list
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
(union_definition "union"     @context name: (identifier) @name) @item
(enum_definition  "enum"      @context name: (identifier) @name) @item
(namespace_definition "namespace" @context name: (qualified_name) @name) @item
(type_alias       "type"      @context name: (identifier) @name) @item

(preproc_module "#module" @context name: (string) @name) @item
(preproc_import "#import" @context path: (string) @name) @item
(preproc_macro  "#macro"  @context name: (identifier) @name) @item
(preproc_define "#define" @context name: (identifier) @name) @item
