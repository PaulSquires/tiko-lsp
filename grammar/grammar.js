/// <reference types="tree-sitter-cli/dsl" />

// tree-sitter-tiko
//
// A grammar for tiko -- the FreeBASIC-compatible language of tiko-lang --
// written for EDITORS: highlighting, folding, an outline and indentation. It is
// deliberately NOT a compiler front end, and the difference shows in two
// places.
//
// 1. THE INSIDE OF A STATEMENT IS A SEQUENCE OF ATOMS, not an expression tree.
//    tiko's expression grammar is large and ambiguous by design -- `Foo(1)` is
//    a call, an array index or a cast depending on what Foo is -- and none of
//    that changes how the text is coloured. What an editor needs is the BLOCK
//    STRUCTURE and the token kinds; both are cheap to get exactly right, and a
//    grammar that ERRORs on real code highlights nothing at all.
//
// 2. ONLY STRUCTURAL WORDS ARE KEYWORDS HERE. `sub`, `end`, `if`, `for` and
//    their kind appear in the rules because they delimit blocks. The other two
//    hundred reserved words -- `print`, `mod`, `andalso`, `sizeof` -- are
//    ordinary identifiers to this grammar and are coloured by a `#match?`
//    predicate in highlights.scm instead.
//
//    That is not a shortcut, it is the fix. tiko is CASE-INSENSITIVE, so every
//    keyword is a regex rather than a string, which switches off tree-sitter's
//    keyword extraction; a two-hundred-word `keyword` rule then collides with
//    `identifier` in the lexer at every turn. Moving the list to the query
//    removes the ambiguity entirely and puts a case-insensitive word list
//    where a case-insensitive word list belongs.
//
// THREE THINGS ABOUT THE LANGUAGE that shape everything below:
//
//   * KEYWORDS ARE CASE-INSENSITIVE: `Sub`, `sub` and `SUB` are one word.
//   * STATEMENTS END AT A NEWLINE, or at a colon. A newline is therefore a
//     real token and cannot live in `extras`.
//   * A LINE CONTINUES WITH `_`. That one IS in extras, which makes a wrapped
//     statement identical to an unwrapped one everywhere else.

/** Case-insensitive keyword: `sub` matches Sub, SUB, sUb. */
function kw(word) {
  return alias(
    token(prec(2, new RegExp(
      word.split('').map(c => `[${c.toLowerCase()}${c.toUpperCase()}]`).join('')
    ))),
    word,
  );
}

/** `end sub`, `end if` -- one token, so a closer can never be read as the
 *  `end <expression>` statement with the block word as its value. Longest
 *  match settles it in the lexer, where there is no conflict to lose. */
function endkw(word) {
  return alias(
    token(prec(3, new RegExp(
      '[eE][nN][dD][ \\t]+' +
      word.split('').map(c => `[${c.toLowerCase()}${c.toUpperCase()}]`).join('')
    ))),
    'end ' + word,
  );
}

/** A case-insensitive alternation, for directive names. */
function ciAlt(words) {
  return new RegExp(
    '(' + words.map(w => w.split('')
      .map(c => `[${c.toLowerCase()}${c.toUpperCase()}]`).join('')).join('|') + ')'
  );
}

function commaSep1(rule) {
  return seq(rule, repeat(seq(',', rule)));
}

module.exports = grammar({
  name: 'tiko',

  extras: $ => [
    /[ \t\r]/,
    $.line_continuation,
    $.comment,
  ],

  conflicts: $ => [

    // An enum body holds members -- `A = 1,` -- and, in tiko-lang's own
    // headers, list-macro calls: `TKO_OPT_LIST( OPT )`. Both start with a
    // name, and only what follows tells them apart.
    [$.enum_member, $._atom],

    // `private:` inside a TYPE is an access specifier; `private const x = 1`
    // is a statement with modifiers. The colon is what tells them apart, one
    // token too late for LR.
    [$.access_specifier, $.modifier],

  ],

  externals: $ => [$._eof],

  word: $ => $._word,

  rules: {
    source_file: $ => repeat($._item),

    _item: $ => choice(
      $._terminator,
      $.preproc,
      $._declaration,
      $._statement,
    ),

    // A statement ends at a newline or a colon, and a run of them is not an
    // error -- blank lines are how source is spaced.
    _terminator: _ => choice('\n', ':'),

    // THE END OF THE FILE ENDS A LINE TOO. An editor buffer spends most of its
    // life without a trailing newline -- the caret is on the last line, still
    // typing it -- and a grammar that insists on one reports the whole last
    // statement as broken exactly while it is being written. `_eof` is a
    // zero-width token from the external scanner, and it is used ONLY as the
    // tail of something that has already consumed text: put it in a repetition
    // of its own and the parser would take it forever.
    _line_end: $ => choice($._terminator, $._eof),

    // `_` continues a line, and a COMMENT may follow it -- which is how a
    // wrapped argument list gets a note against each argument. Reading the
    // underscore without allowing that is how four consecutive lines of this
    // project's own tests stopped parsing.
    line_continuation: _ => token(new RegExp(
      "_[ \\t]*('[^\\n]*)?\\r?\\n"
    )),

    comment: _ => token(choice(
      seq("'", /[^\n]*/),
      // REM MUST BE A WHOLE WORD. Without the space after it, `removed`,
      // `remaining` and `Remove` all begin with a comment marker -- the rest
      // of the line disappears into a comment, and every file in this project
      // that counts something `removed` failed to parse because of it.
      seq(/[rR][eE][mM]/, /[ \t][^\n]*/),
      // NOT nested. A nesting comment needs an external scanner in C, and one
      // comment inside another is rare enough that the C file is the wrong
      // trade -- the first closer wins.
      seq("/'", repeat(choice(/[^']/, /'[^\/]/)), "'/"),
    )),

    // ---------------------------------------------------------- preprocessor
    //
    // A directive is its name and then the rest of the line: what is inside is
    // the preprocessor's business, not an editor's. The exception is the path
    // in an #include, which is worth colouring as one.
    preproc: $ => choice(
      $.preproc_include,
      $.preproc_define,
      $.preproc_macro,
      $.preproc_other,
    ),

    preproc_include: $ => seq(
      alias(token(prec(3, seq('#', /[ \t]*/, ciAlt(['include'])))), '#include'),
      optional(kw('once')),
      field('path', $.string),
      $._line_end,
    ),

    preproc_define: $ => seq(
      alias(token(prec(3, seq('#', /[ \t]*/, ciAlt(['define'])))), '#define'),
      field('name', $.identifier),

      // NOT a parameter list. `#define A(x) ...` and `#define A (x + 1)` differ
      // only by the space before the parenthesis -- fbc really does decide on
      // adjacency -- and a body is read as atoms either way, so nothing is
      // gained by telling them apart here.
      repeat($._atom),
      $._line_end,
    ),

    preproc_macro: $ => seq(
      alias(token(prec(3, seq('#', /[ \t]*/, ciAlt(['macro'])))), '#macro'),
      field('name', $.identifier),
      optional($.parameter_list),
      $._line_end,
      repeat($._macro_line),
      alias(token(prec(4, seq('#', /[ \t]*/, ciAlt(['endmacro'])))), '#endmacro'),
      $._line_end,
    ),

    // A MACRO BODY IS TEXT. fbc's own test suite opens a block in one macro and
    // closes it in another, so the body is never required to balance and is not
    // parsed as statements at all.
    _macro_line: $ => choice(
      '\n',
      $.preproc,
      seq(alias(token(prec(-1, /[^#\n][^\n]*/)), $.macro_text), '\n'),
    ),

    preproc_other: $ => seq(
      field('directive', alias(token(prec(3, seq('#', /[ \t]*/, /[a-zA-Z_][a-zA-Z_0-9]*/))),
                               $.preproc_directive)),
      repeat($._atom),
      $._line_end,
    ),

    // ----------------------------------------------------------- declarations
    _declaration: $ => choice(
      $.procedure_definition,
      $.declare_statement,
      $.type_definition,
      $.union_definition,
      $.enum_definition,
      $.type_alias,
      $.namespace_definition,
      $.extern_block,
    ),

    _procedure_keyword: $ => choice(
      kw('sub'), kw('function'), kw('property'),
      kw('constructor'), kw('destructor'), kw('operator'),
    ),

    modifier: $ => choice(
      kw('private'), kw('public'), kw('protected'), kw('static'),
      kw('virtual'), kw('abstract'), kw('shared'), kw('const'),
    ),

    procedure_definition: $ => seq(
      repeat($.modifier),
      field('kind', $._procedure_keyword),
      field('name', $.qualified_name),
      repeat($._signature_tail),
      $._line_end,
      repeat($._body_item),
      field('close', choice(
        endkw('sub'), endkw('function'), endkw('property'),
        endkw('constructor'), endkw('destructor'), endkw('operator'),
      )),
    ),

    declare_statement: $ => seq(
      repeat($.modifier),
      kw('declare'),
      repeat($.modifier),
      field('kind', $._procedure_keyword),
      field('name', $.qualified_name),
      repeat($._signature_tail),
      $._line_end,
    ),

    // `as long`, `byref as string`, a calling convention, `export`, `static`
    // -- and the PARAMETER LIST, which is a tail like any other because it does
    // not come last: `declare sub puts_ cdecl alias "puts" ( ... )` puts two
    // words and a string in front of it.
    _signature_tail: $ => choice(
      seq(kw('as'), field('return_type', $._type)),
      kw('byref'),
      kw('byval'),
      kw('static'),
      kw('const'),
      $.parameter_list,
      $.string,
      $.identifier,
    ),

    parameter_list: $ => seq('(', optional(commaSep1($.parameter)), ')'),

    parameter: $ => choice(
      '...',
      seq(
        optional(choice(kw('byval'), kw('byref'))),
        field('name', $.identifier),
        optional(seq('(', optional(commaSep1($._atom)), ')')),
        optional(seq(kw('as'), field('type', $._type))),
        optional(seq('=', field('default', $._value))),
      ),
      // An unnamed parameter, which a DECLARE may write: `declare sub f( as long )`.
      seq(optional(choice(kw('byval'), kw('byref'))), kw('as'), field('type', $._type)),
    ),

    type_definition: $ => seq(
      repeat($.modifier),
      kw('type'),
      field('name', $.identifier),
      repeat($._type_header_tail),
      $._line_end,
      repeat($._type_member),
      endkw('type'),
    ),

    union_definition: $ => seq(
      repeat($.modifier),
      kw('union'),
      optional(field('name', $.identifier)),
      $._line_end,
      repeat($._type_member),
      endkw('union'),
    ),

    _type_header_tail: $ => choice(
      seq(kw('extends'), field('base', $._type)),
      seq(kw('field'), '=', $.number),
      $.generic_parameters,
    ),

    // `( of T )`, and `( of MirFunction ptr )` -- each argument is a TYPE, so
    // it is a run of words rather than a single one.
    generic_parameters: $ => seq('(', kw('of'), commaSep1($._value), ')'),

    _type_member: $ => choice(
      $._terminator,
      $.preproc,
      $.access_specifier,
      $.procedure_definition,
      $.declare_statement,
      $.type_definition,
      $.union_definition,
      $.enum_definition,
      $._statement,
    ),

    access_specifier: $ => seq(
      choice(kw('private'), kw('public'), kw('protected')),
      ':',
    ),

    enum_definition: $ => seq(
      repeat($.modifier),
      kw('enum'),
      optional(field('name', $.identifier)),
      optional(kw('explicit')),
      $._line_end,
      repeat(choice($._terminator, $.preproc, $.enum_member, $._simple_statement)),
      endkw('enum'),
    ),

    enum_member: $ => seq(
      field('name', $.identifier),
      optional(seq('=', $._atoms)),
      optional(','),
      $._line_end,
    ),

    // `type Handle as any ptr` -- a typedef, and not a block.
    type_alias: $ => seq(
      kw('type'),
      field('name', $.identifier),
      kw('as'),
      field('type', $._type),
      $._line_end,
    ),

    namespace_definition: $ => seq(
      kw('namespace'),
      field('name', $.qualified_name),
      $._line_end,
      repeat($._body_item),
      endkw('namespace'),
    ),

    extern_block: $ => seq(
      kw('extern'),
      repeat(choice($.string, $.identifier)),
      $._line_end,
      repeat($._body_item),
      endkw('extern'),
    ),

    // ------------------------------------------------------------ statements
    _body_item: $ => choice(
      $._terminator,
      $.preproc,
      $._declaration,
      $._statement,
    ),

    _statement: $ => choice(
      $.if_statement,
      $.if_single_line,
      $.select_statement,
      $.for_statement,
      $.while_statement,
      $.do_statement,
      $.scope_block,
      $.with_block,
      $.asm_block,
      $.exit_statement,
      $.end_statement,
      $.label,
      $.open_statement,
      $.result_assignment,
      $.end_with_value,
      $.modified_statement,
      $._simple_statement,
    ),

    // `const X = 1`, `static as long n`, `private shared foo = 2`. The
    // modifiers are structural words, so they cannot be atoms -- but the rest
    // of the line is atoms like any other statement.
    modified_statement: $ => prec.right(seq(
      repeat1($.modifier),
      optional($._atoms),
    )),

    if_statement: $ => seq(
      kw('if'),
      field('condition', $._atoms),
      kw('then'),
      $._line_end,
      repeat($._body_item),
      repeat($.elseif_clause),
      optional($.else_clause),
      choice(endkw('if'), kw('endif')),
    ),

    elseif_clause: $ => prec.right(seq(
      choice(kw('elseif'), seq(kw('else'), kw('if'))),
      field('condition', $._atoms),
      kw('then'),
      $._line_end,
      repeat($._body_item),
    )),

    else_clause: $ => prec.right(seq(
      kw('else'),
      $._line_end,
      repeat($._body_item),
    )),

    // `if x then y = 1 else y = 2` -- one line, no closer.
    if_single_line: $ => prec.right(seq(
      kw('if'),
      field('condition', $._atoms),
      kw('then'),
      $._inline_statement,
      repeat(seq(':', $._inline_statement)),
      optional(seq(kw('else'), $._inline_statement, repeat(seq(':', $._inline_statement)))),
    )),

    _inline_statement: $ => choice(
      $.exit_statement,
      $.end_statement,
      $._simple_statement,
    ),

    select_statement: $ => seq(
      kw('select'),
      kw('case'),
      // `select case as const x` -- a jump table rather than a chain of tests.
      optional(seq(kw('as'), kw('const'))),
      field('value', $._atoms),
      $._line_end,
      // Between `select case x` and the first `case` there is usually nothing
      // -- but tiko-lang's own code puts a `#define` and a list-macro call
      // there, which build the arms.
      repeat(choice($._terminator, $.preproc, $._simple_statement)),
      repeat($.case_clause),
      endkw('select'),
    ),

    case_clause: $ => prec.right(seq(
      kw('case'),
      // `case else` is not a value, and `else` is structural everywhere else.
      choice(kw('else'), seq(optional(kw('is')), field('value', $._atoms))),
      repeat($._body_item),
    )),

    // `next` may name the variable it closes -- `next i` -- and the line after
    // it may equally start with a name. The closer takes the longer reading,
    // which is what fbc does.
    for_statement: $ => prec.right(seq(
      kw('for'),
      field('variable', $._atoms),
      $._line_end,
      repeat($._body_item),
      kw('next'),
      optional(commaSep1($.identifier)),
    )),

    while_statement: $ => seq(
      kw('while'),
      field('condition', $._atoms),
      $._line_end,
      repeat($._body_item),
      // BOTH SPELLINGS. `wend` is the old one and `end while` the one every
      // block-structured dialect writes; a grammar that knows only `wend`
      // loses the rest of the file the first time it meets the other.
      choice(kw('wend'), endkw('while')),
    ),

    // `loop` may be followed by `while`/`until`, and the line after it may
    // START with one; only the end of the line tells them apart, so the closer
    // takes the longer reading.
    do_statement: $ => prec.right(seq(
      kw('do'),
      optional(seq(choice(kw('while'), kw('until')), field('condition', $._atoms))),
      $._line_end,
      repeat($._body_item),
      kw('loop'),
      optional(seq(choice(kw('while'), kw('until')), field('condition', $._atoms))),
    )),

    scope_block: $ => seq(
      kw('scope'),
      optional($._atoms),
      $._line_end,
      repeat($._body_item),
      endkw('scope'),
    ),

    with_block: $ => seq(
      kw('with'),
      $._atoms,
      $._line_end,
      repeat($._body_item),
      endkw('with'),
    ),

    // Assembly is not tiko, and reading it as tiko produces nonsense.
    asm_block: $ => seq(
      kw('asm'),
      $._line_end,
      repeat(choice('\n', seq(alias(token(prec(-1, /[^\n]+/)), $.asm_text), '\n'))),
      endkw('asm'),
    ),

    exit_statement: $ => prec.right(seq(
      choice(kw('exit'), kw('continue')),
      commaSep1(choice(
        kw('sub'), kw('function'), kw('property'), kw('constructor'),
        kw('destructor'), kw('operator'), kw('for'), kw('while'), kw('do'),
        kw('select'), $.identifier,
      )),
    )),

    // `end`, and `end 1` -- the statement that STOPS THE PROGRAM, spelled with
    // the same word every block closes with.
    //
    // It is one token, newline included, and that is the whole trick: `end` as
    // a statement is `end` at the END OF A LINE, while `end sub` and `end if`
    // have a word after them. Written as two symbols instead, the statement
    // and the closer compete inside every block body -- and the statement wins
    // silently, swallowing the `end if` that was meant to close the block and
    // then everything after it to the end of the file.
    end_statement: _ => token(prec(3, new RegExp(
      '[eE][nN][dD][ \\t]*[0-9]*[ \\t]*\\r?\\n'
    ))),

    // `end WriteSession( path_ )` -- END takes an expression, and its value is
    // the process's exit code.
    //
    // Safe next to every `end sub` and `end select` because a closer's word is
    // a KEYWORD token and an atom can never be one: `end if` cannot be read
    // this way even when both are possible, because `if` is not an atom.
    end_with_value: $ => prec(-2, seq(kw('end'), $._atoms)),

    // `again:` -- a jump target, and the one place a colon is not a separator.
    label: $ => prec(2, seq(field('name', $.identifier), ':', '\n')),

    // THE RETURN VALUE IS ASSIGNED TO THE PROCEDURE WORD: `function = 0`,
    // `property = this.x`. The word is structural everywhere else, so without
    // this rule the commonest statement in a hand-written FreeBASIC codebase
    // opens a procedure that is never closed -- 222 files of one project here
    // failed on that one line shape.
    result_assignment: $ => seq(
      field('kind', choice(kw('function'), kw('property'), kw('operator'))),
      '=',
      $._atoms,
    ),

    // `open "f" for output as #fh`, `open err for output as #fh`. The words
    // FOR and AS are structural everywhere else, so left as tokens this line
    // opens a loop that is never closed and the rest of the file is lost. The
    // whole line is one token, and the highlight query colours inside it.
    open_statement: $ => seq(
      alias(token(prec(2, new RegExp('[oO][pP][eE][nN][ \\t][^\\n\':]*'))), $.open_text),
      $._line_end,
    ),

    _simple_statement: $ => $._atoms,

    // A run of atoms, taken GREEDILY. Every place that reads "the rest of the
    // line" uses this one rule, so the parser never has to decide between
    // stopping here and continuing -- it always continues.
    _atoms: $ => prec.right(repeat1($._atom)),

    // ----------------------------------------------------------------- atoms
    //
    // Everything a statement can contain that is not structure. Block keywords
    // are deliberately absent, which is what stops a statement from swallowing
    // an `end sub`.
    _atom: $ => choice(
      $.string,
      $.number,
      $.identifier,
      $.operator,
      ',', '.', '=', '...',

      // PARENTHESES ARE BALANCED HERE, and that is doing real work: inside a
      // pair, the grammar expects nothing but atoms, so the lexer reads
      // `open( p FOR binary access read AS #f )` as words rather than as the
      // FOR and AS that open a loop and a type. Bare `(` and `)` atoms left
      // those words structural everywhere, and every statement that borrows
      // one -- OPEN, PRINT #, LINE INPUT -- was an error.
      seq('(', repeat($._nested_atom), ')'),
      seq('[', repeat($._nested_atom), ']'),

      // An array or UDT initialiser: `= { 1, 2, 3 }`.
      seq('{', repeat($._nested_atom), '}'),

      // `type( a, b )` and `type<POINT>( x, y )` -- a UDT literal. TYPE opens a
      // block everywhere else; here it is the constructor, and what follows the
      // word is the only thing that tells them apart.
      $.type_literal,
    ),

    type_literal: $ => seq(
      kw('type'),
      optional(seq('<', repeat($._nested_atom), '>')),
      '(', repeat($._nested_atom), ')',
    ),

    // A default value, and anything else written inside a list.
    _value: $ => prec.right(repeat1($._value_atom)),

    _value_atom: $ => choice(
      $.string, $.number, $.identifier, $.operator, '.', '=',
      seq('(', repeat($._nested_atom), ')'),
      seq('[', repeat($._nested_atom), ']'),

      // An array or UDT initialiser: `= { 1, 2, 3 }`.
      seq('{', repeat($._nested_atom), '}'),
    ),

    // Inside a pair of parentheses a comma is just punctuation again.
    _nested_atom: $ => choice($._value_atom, ','),

    _type: $ => prec.right(repeat1(choice(
      $.identifier,
      '.', '*',
      // The only parentheses a TYPE can carry: a generic's arguments, or the
      // parameters of a function pointer. Anything else in parentheses
      // belongs to the statement around the type, not to the type.
      $.generic_parameters,
      $.parameter_list,

      // The return type of a function pointer: `as function( ... ) AS long`.
      kw('as'),
    ))),

    operator: _ => token(choice(
      '+', '-', '*', '/', '\\', '^', '&', '@', '<', '>', '<=', '>=', '<>',
      '+=', '-=', '*=', '/=', '\\=', '&=', '^=', '=>', '->', '?', '!', '#', '$',
      ';',
    )),

    // `Customer.SetName`, and `Optional( of T ).HasValue` -- a generic's type
    // arguments are part of the name, which is what keeps the member out of
    // the signature.
    qualified_name: $ => prec.left(seq(
      $.identifier,
      optional($.generic_parameters),
      repeat(seq('.', $.identifier, optional($.generic_parameters))),
    )),

    identifier: $ => $._word,

    _word: _ => token(/[a-zA-Z_][a-zA-Z_0-9]*[$%&!#]?/),

    number: _ => token(choice(
      /&[hH][0-9a-fA-F]+([uU]?[lL]{0,2})?/,
      /&[oO][0-7]+([uU]?[lL]{0,2})?/,
      /&[bB][01]+([uU]?[lL]{0,2})?/,
      /[0-9]+\.?[0-9]*([eEdD][+-]?[0-9]+)?([uUlLfFdD!#%&]{0,3})?/,
      /\.[0-9]+([eEdD][+-]?[0-9]+)?([uUlLfFdD!#%&]{0,3})?/,
    )),

    string: _ => token(choice(
      seq(
        optional(/[!$]/),
        '"',
        repeat(choice(/[^"\n]/, '""')),
        '"',
      ),

      // AN UNTERMINATED STRING ENDS AT THE LINE, and that is not a courtesy:
      // fbc accepts one, tiko-lang's own sources contain one, and an editor
      // sees one on every keystroke while a string is being typed. Lower
      // precedence, so a closed string is always preferred.
      prec(-1, seq(optional(/[!$]/), '"', repeat(/[^"\n]/))),
    )),
  },
});
