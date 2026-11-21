#include "tree_sitter/parser.h"

// Four things the grammar cannot express.
//
// END OF FILE ENDS A LINE.
//
// A statement in tiko ends at a newline or a colon, and neither exists after
// the last line of a buffer that has no trailing newline -- which is every
// buffer being typed into. Without this the last statement parses as an error
// while it is being written, and the editor colours it as broken.
//
// The token is ZERO WIDTH, so it must only ever be reachable as the tail of a
// rule that has already consumed text; the grammar uses it through `_line_end`
// alone, never in a bare repetition.
//
// `interface` AND `inherits` ARE CONTEXTUAL WORDS.
//
// Neither is reserved -- fbc takes both as names, winddk.bi uses `interface`
// as a type, a field and a parameter, and tiko-lang's interface-as-name test
// keeps every such use. As a keyword token either one lexes as the keyword
// wherever a name is valid too (the `link`/`channel` trap), so `print
// interface` and `dim as long inherits = 2` break. Here each is a keyword
// only where the parser can take one (`valid_symbols`) AND a name follows on
// the line: `interface IAnimal`, `inherits Animal` -- not `inherits as long`,
// a field, nor `interface = 3`. Anything else is left to the lexer, which
// reads the word as an identifier.
//
// `as view` ENDS AT A WORD BOUNDARY.
//
// tiko's view-kind type, `type Lexer as view`, is a block where `type X as Y`
// is an alias. As one lexer token `as view` would also match the front of
// `type V as viewport`, and tree-sitter's regexes have no lookahead -- so the
// boundary after `view` is checked here, only where the parser can take it.

//
// `match` IS CONTEXTUAL (tiko-lang RFC-0001-match 5.2).
//
// It is a name everywhere fbc takes one -- `dim as long match`, `match = 3`,
// `sub match`, `match( 21 )`, the paren-less call `match 10`, and `end match`
// as END with an exit code. It is the keyword only where the parser can take
// one AND
//   * something follows it on its line (the subject), not `=`, `.` or `:`;
//   * the next non-blank line begins with `case` (the statement form) or holds
//     a `=>` outside brackets and strings (the value form); and
//   * an `end match` begins a later line before an unmatched `end select` --
//     which keeps `match 10` a call inside a SELECT arm followed by `case 2`.
// The two forms are two tokens, so the parser never has to guess which block
// it is in: the next line has already said.

enum TokenType {
    EOF_LINE_END,
    INTERFACE_KW,
    INHERITS_KW,
    AS_VIEW_KW,
    PARTIAL_KW,
    MATCH_KW,
    MATCH_VALUE_KW,
};

void *tree_sitter_tiko_external_scanner_create(void) { return NULL; }
void tree_sitter_tiko_external_scanner_destroy(void *payload) { }

unsigned tree_sitter_tiko_external_scanner_serialize(void *payload, char *buffer) { return 0; }
void tree_sitter_tiko_external_scanner_deserialize(void *payload, const char *buffer, unsigned length) { }

static bool is_ident_start(int32_t c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

static bool is_ident_char(int32_t c) {
    return is_ident_start(c) || (c >= '0' && c <= '9');
}

static bool same(const char *a, const char *b, int n) {
    for (int i = 0; i < n; i++) if (a[i] != b[i]) return false;
    return true;
}

static int32_t lower(int32_t c) {
    return (c >= 'A' && c <= 'Z') ? c + ('a' - 'A') : c;
}

// After the keyword: blanks, then a name that is not `as`.
static bool name_follows(TSLexer *lexer) {
    if (lexer->lookahead != ' ' && lexer->lookahead != '\t') return false;
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') lexer->advance(lexer, false);
    if (!is_ident_start(lexer->lookahead)) return false;

    int32_t a = lower(lexer->lookahead);
    lexer->advance(lexer, false);
    if (a != 'a' || lower(lexer->lookahead) != 's') return true;
    lexer->advance(lexer, false);
    return is_ident_char(lexer->lookahead);     // `asset` is a name, `as` is not
}

// After `partial`: blanks, then `type` or `class` with no name character after it. Only that
// makes it the keyword; `partial` is an ordinary name anywhere else.
static bool type_follows(TSLexer *lexer) {
    if (lexer->lookahead != ' ' && lexer->lookahead != '\t') return false;
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') lexer->advance(lexer, false);
    const char *word = lower(lexer->lookahead) == 'c' ? "class" : "type";
    for (int i = 0; word[i]; i++) {
        if (lower(lexer->lookahead) != word[i]) return false;
        lexer->advance(lexer, false);
    }
    return !is_ident_char(lexer->lookahead);
}

// `as`, blanks, `view`, and no name character after it.
static bool scan_as_view(TSLexer *lexer) {
    if (lower(lexer->lookahead) != 'a') return false;
    lexer->advance(lexer, false);
    if (lower(lexer->lookahead) != 's') return false;
    lexer->advance(lexer, false);
    if (lexer->lookahead != ' ' && lexer->lookahead != '\t') return false;
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') lexer->advance(lexer, false);
    const char *view = "view";
    for (int i = 0; i < 4; i++) {
        if (lower(lexer->lookahead) != view[i]) return false;
        lexer->advance(lexer, false);
    }
    if (is_ident_char(lexer->lookahead)) return false;     // `viewport` is a name
    lexer->mark_end(lexer);
    lexer->result_symbol = AS_VIEW_KW;
    return true;
}

// ---- `match`: everything below reads ahead and never consumes (mark_end is
// already behind the word).

static bool at_eof(TSLexer *lexer) { return lexer->eof(lexer); }

static void skip_blanks(TSLexer *lexer) {
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t' || lexer->lookahead == '\r') {
        lexer->advance(lexer, false);
    }
}

// A word, lower-cased into `buf` (NUL-terminated); returns its length, or
// max + 1 when it is longer than `max`.
static int read_word(TSLexer *lexer, char *buf, int max) {
    int n = 0;
    while (is_ident_char(lexer->lookahead)) {
        if (n < max) buf[n] = (char)lower(lexer->lookahead);
        n++;
        lexer->advance(lexer, false);
    }
    if (n > max) n = max + 1;
    buf[n <= max ? n : max] = 0;
    return n;
}

// To just past the end of the LOGICAL line: a `_` ending a line (before any
// comment) carries it on. Strings and comments are stepped over. False at EOF.
static bool skip_line(TSLexer *lexer) {
    bool last_underscore = false;   // the last significant thing was a lone `_`
    int32_t prev = ' ';
    for (;;) {
        if (at_eof(lexer)) return false;
        int32_t c = lexer->lookahead;
        if (c == '\n') {
            lexer->advance(lexer, false);
            if (!last_underscore) return true;
            last_underscore = false;
            prev = ' ';
            continue;
        }
        if (c == '\'') {                                    // a comment to the line's end
            while (!at_eof(lexer) && lexer->lookahead != '\n') lexer->advance(lexer, false);
            continue;
        }
        if (c == '"') {
            lexer->advance(lexer, false);
            while (!at_eof(lexer) && lexer->lookahead != '"' && lexer->lookahead != '\n') {
                lexer->advance(lexer, false);
            }
            if (lexer->lookahead == '"') lexer->advance(lexer, false);
            last_underscore = false;
            prev = '"';
            continue;
        }
        if (c == ' ' || c == '\t' || c == '\r') {
            lexer->advance(lexer, false);
            prev = ' ';
            continue;
        }
        lexer->advance(lexer, false);
        last_underscore = c == '_' && !is_ident_char(prev) && !is_ident_char(lexer->lookahead);
        prev = c;
    }
}

// Does the rest of this line hold `=>` outside brackets and strings?
static bool line_has_arrow(TSLexer *lexer) {
    int depth = 0;
    while (!at_eof(lexer) && lexer->lookahead != '\n') {
        int32_t c = lexer->lookahead;
        if (c == '\'') return false;
        lexer->advance(lexer, false);
        if (c == '"') {
            while (!at_eof(lexer) && lexer->lookahead != '"' && lexer->lookahead != '\n') {
                lexer->advance(lexer, false);
            }
            if (lexer->lookahead == '"') lexer->advance(lexer, false);
        } else if (c == '(' || c == '[' || c == '{') {
            depth++;
        } else if (c == ')' || c == ']' || c == '}') {
            if (depth > 0) depth--;
        } else if (c == '=' && depth == 0 && lexer->lookahead == '>') {
            return true;
        }
    }
    return false;
}

// Does a line beginning with `end match` come before an unmatched `end select`?
// The lexer stands at the start of a line.
static bool end_match_follows(TSLexer *lexer) {
    int selects = 0;
    char word[8];
    for (;;) {
        skip_blanks(lexer);
        if (at_eof(lexer)) return false;
        int n = read_word(lexer, word, 6);
        if (n == 3 && same(word, "end", 3)) {
            if (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
                skip_blanks(lexer);
                n = read_word(lexer, word, 6);
                if (n == 5 && same(word, "match", 5)) return true;
                if (n == 6 && same(word, "select", 6)) {
                    if (selects == 0) return false;
                    selects--;
                }
            }
        } else if (n == 6 && same(word, "select", 6)) {
            selects++;
        }
        if (!skip_line(lexer)) return false;
    }
}

// After the word `match` (mark_end already set): which form, if either?
static bool scan_match(TSLexer *lexer, bool want_stmt, bool want_value) {
    // A subject on the line. Not `match = 3`, `match.x`, `match:`, `match`,
    // nor a suffixed name, `match$`.
    int32_t c = lexer->lookahead;
    if (c == '$' || c == '%' || c == '&' || c == '!' || c == '#') return false;
    skip_blanks(lexer);
    c = lexer->lookahead;
    if (at_eof(lexer) || c == '\n' || c == '\'' || c == ':' || c == '=' || c == '.' ||
        c == ',' || c == ')' || c == ']' || c == '}' || c == ';') {
        return false;
    }
    if (c == '-') {
        lexer->advance(lexer, false);
        if (lexer->lookahead == '>') return false;          // `match->x`
    }
    if (!skip_line(lexer)) return false;

    // The next non-blank line, past comment-only ones.
    for (;;) {
        skip_blanks(lexer);
        if (at_eof(lexer)) return false;
        if (lexer->lookahead == '\n') { lexer->advance(lexer, false); continue; }
        if (lexer->lookahead == '\'') {
            if (!skip_line(lexer)) return false;
            continue;
        }
        break;
    }

    char word[8];
    int n = read_word(lexer, word, 4);
    enum TokenType found;
    if (n == 4 && same(word, "case", 4)) {
        if (!want_stmt) return false;
        found = MATCH_KW;
    } else {
        if (!want_value || !line_has_arrow(lexer)) return false;
        found = MATCH_VALUE_KW;
    }
    if (!skip_line(lexer)) return false;
    if (!end_match_follows(lexer)) return false;
    lexer->result_symbol = found;
    return true;
}

bool tree_sitter_tiko_external_scanner_scan(void *payload, TSLexer *lexer,
                                            const bool *valid_symbols) {
    if (valid_symbols[EOF_LINE_END] && lexer->eof(lexer)) {
        lexer->result_symbol = EOF_LINE_END;
        return true;
    }

    // Error recovery offers every token at once; a keyword guessed there
    // would only make the recovery worse.
    bool want_interface = valid_symbols[INTERFACE_KW];
    bool want_inherits = valid_symbols[INHERITS_KW];
    bool want_as_view = valid_symbols[AS_VIEW_KW];
    bool want_partial = valid_symbols[PARTIAL_KW];
    bool want_match = valid_symbols[MATCH_KW];
    bool want_match_value = valid_symbols[MATCH_VALUE_KW];
    if (want_interface && want_inherits && valid_symbols[EOF_LINE_END]) return false;
    if (want_as_view && (want_interface || want_inherits)) return false;

    if (want_as_view) {
        while (lexer->lookahead == ' ' || lexer->lookahead == '\t' || lexer->lookahead == '\r') {
            lexer->advance(lexer, true);
        }
        return scan_as_view(lexer);
    }
    if (!want_interface && !want_inherits && !want_partial && !want_match && !want_match_value) {
        return false;
    }

    while (lexer->lookahead == ' ' || lexer->lookahead == '\t' || lexer->lookahead == '\r') {
        lexer->advance(lexer, true);
    }

    char word[10];
    int n = 0;
    while (is_ident_char(lexer->lookahead)) {
        if (n == 9) return false;
        word[n++] = (char)lower(lexer->lookahead);
        lexer->advance(lexer, false);
    }
    word[n] = 0;

    enum TokenType found;
    if (want_interface && n == 9 && same(word, "interface", 9)) {
        found = INTERFACE_KW;
    } else if (want_inherits && n == 8 && same(word, "inherits", 8)) {
        found = INHERITS_KW;
    } else if (want_partial && n == 7 && same(word, "partial", 7)) {
        lexer->mark_end(lexer);
        if (!type_follows(lexer)) return false;
        lexer->result_symbol = PARTIAL_KW;
        return true;
    } else if ((want_match || want_match_value) && n == 5 && same(word, "match", 5)) {
        lexer->mark_end(lexer);
        return scan_match(lexer, want_match, want_match_value);
    } else {
        return false;
    }

    lexer->mark_end(lexer);
    if (!name_follows(lexer)) return false;
    lexer->result_symbol = found;
    return true;
}
