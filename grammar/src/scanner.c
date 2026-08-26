#include "tree_sitter/parser.h"

// The one thing the grammar cannot express: END OF FILE ENDS A LINE.
//
// A statement in tiko ends at a newline or a colon, and neither exists after
// the last line of a buffer that has no trailing newline -- which is every
// buffer being typed into. Without this the last statement parses as an error
// while it is being written, and the editor colours it as broken.
//
// The token is ZERO WIDTH, so it must only ever be reachable as the tail of a
// rule that has already consumed text; the grammar uses it through `_line_end`
// alone, never in a bare repetition.

enum TokenType {
    EOF_LINE_END,
};

void *tree_sitter_tiko_external_scanner_create(void) { return NULL; }
void tree_sitter_tiko_external_scanner_destroy(void *payload) { }

unsigned tree_sitter_tiko_external_scanner_serialize(void *payload, char *buffer) { return 0; }
void tree_sitter_tiko_external_scanner_deserialize(void *payload, const char *buffer, unsigned length) { }

bool tree_sitter_tiko_external_scanner_scan(void *payload, TSLexer *lexer,
                                            const bool *valid_symbols) {
    if (valid_symbols[EOF_LINE_END] && lexer->eof(lexer)) {
        lexer->result_symbol = EOF_LINE_END;
        return true;
    }
    return false;
}
