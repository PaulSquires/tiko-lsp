# Architecture

## Layering

Each layer knows only about the one below it.

```
main.bas            arguments, the message loop, the exit code
  |
lsp/dispatcher      lifecycle state machine, handler registry
  |                 knows LSP, does not know how bytes are framed
handlers/*          one function per method; build a result, or set an error
  |                        |
  |                        +--> document/*   open buffers, edits, line index
  |                        +--> analysis/*   lexer, parser, symbols,
  |                        |                 completion, diagnostics
  |                        +--> workspace/*  discovery, the symbol index
  |                        +--> format/semantic/signature (phase 7)
  |                        +--> utils/*      positions, URIs, logging
rpc/jsonrpc         jsonrpc / id / method / params / result / error
  |                 knows JSON-RPC, does not know LSP
rpc/transport       Content-Length framing; stdin and stdout
  |                 knows bytes, does not know JSON
json/json           JsonDoc, JsonValue, JsonBuilder, JsonNode
                    the ONLY place yyjson is named
```

The direction that matters is the one that is missing: no lower layer calls
upwards, and no handler touches a byte or a yyjson symbol.

### Why the JSON library is behind a facade

`json.bi` and `json.bas` are the only two files that include `yyjson.bi`. Replacing
yyjson means rewriting those two and nothing else. The facade also enforces two
yyjson rules that are silent when broken — see "Traps that cost a run" below.

### Why the compiler frontend is not here yet

`Server` and the handlers deal in `RpcMessage` and `JsonBuilder`, never in text
offsets or tokens. When the compiler frontend arrives it plugs in under
`src/analysis/` and hands the handlers symbols; the dispatcher does not change.
This is what keeps "run the compiler as a subprocess" from ever becoming tempting:
there is no place in the design where a process boundary would fit.

## Ownership

| Type | Owns | Rule |
| --- | --- | --- |
| `JsonDoc` | one parsed `yyjson_doc` | frees it; copy and assignment deep-copy |
| `JsonValue` | nothing | borrows a node; dies with its `JsonDoc` |
| `JsonBuilder` | one `yyjson_mut_doc` | frees it and every node in it |
| `JsonNode` | nothing | borrows a node; dies with its `JsonBuilder` |
| `RpcMessage` | its `JsonDoc` | `Params()` is derived, never stored, so a copied message never views the original |
| `MessageFramer` | its byte buffer | compacts once the consumed prefix passes 64 KB |
| `DocumentManager` | every `TextDocument` it opened | `new` on open, `delete` on close; frees the rest in its destructor |
| `TextDocumentPtr` | nothing | borrowed; valid until that document is closed |
| `Server` | its `DocumentManager` | holds a `StdioTransport ptr` it does not free |
| `SymbolTable` | its symbols | a value, with PARENT INDICES rather than pointers: copying it copies everything, and no symbol outlives its table |
| `SymbolIndex` | one `SymbolTable` per file | keyed on the RESOLVED PATH, not the URI, so one file cannot be indexed twice |
| `TokenArray`, `DiagnosticArray` | their elements | plain values, no pointers, freed with the array |

There are no smart pointers and no shared ownership anywhere in the server. Every
allocation has exactly one owner whose destructor releases it.

Documents are stored as pointers rather than by value on purpose: a handler may
hold a `TextDocumentPtr` across a call, and a value-typed table would move its
contents on rehash. Re-opening a URI that is already open therefore refills the
existing object instead of replacing it.

## The lifecycle rules

All of them live in `Server.Dispatch`, and each is asserted by the piped-session
test:

| Situation | Response |
| --- | --- |
| request other than `initialize` before initialisation | error `-32002` ServerNotInitialized |
| notification other than `exit` before initialisation | dropped, logged, no reply |
| second `initialize` | error `-32600` InvalidRequest |
| any request after `shutdown` | error `-32600` InvalidRequest |
| unknown request | error `-32601` MethodNotFound |
| unknown `$/...` notification | ignored in silence |
| unparseable payload | error against a **null** id |
| `exit` | process ends: 0 if `shutdown` came first, else 1 |
| stdin closes with no `exit` | process ends 1 (0 if `shutdown` had been received) |

A notification never produces a reply, including when its handler fails — the
failure is logged instead, because there is no id to answer.

## Analysis

`analysis/` knows nothing about LSP: the lexer and parser work in BYTE OFFSETS
and produce `Diagnostic` and `SymbolInfo` records, and `lsp/publish.bas` is the
only place an offset becomes a line and a UTF-16 character. That is what will let the same
analyser be driven by a command-line tool, or replaced by the real compiler
frontend, without touching a handler.

The parser is structural, not semantic — see
[phase3.md](phase3.md#what-is-checked) for exactly what it checks, and
[phase3.md](phase3.md#false-positives-are-the-failure-mode-that-matters) for the
corpus it was developed against and why that mattered more than the sample
tests.

The same pass builds the SYMBOL TABLE: the block stack already knew the kind,
name and extent of every `sub`, `type`, `enum` and `namespace`, so extracting
symbols cost a second walk over nothing. `documentSymbol`, `hover` and
`definition` all read that one table, which is why they cannot disagree —
see [phase4.md](phase4.md#resolution).

A document analyses itself AT MOST ONCE PER VERSION: `Tokens()`, `Symbols()` and
`Diagnostics()` re-analyse first if the text changed, so four features asking
after one edit cost one analysis, and no caller has to know whether the cache is
warm.

Completion reads the same table and adds the one piece of type knowledge the
server has: a variable's DECLARED TYPE NAME, read out of its detail and looked
up. See [phase5.md](phase5.md#the-type-knowledge-behind-customer) for what that
does and does not reach.

`workspace/` holds the same analysis applied to every file in the folders the
client named: one `SymbolTable` per file, so a change replaces one entry rather
than rebuilding a flat list. What it deliberately does NOT hold is the text --
name ranges are converted to line/character AT INDEX TIME, because turning an
offset into a UTF-16 column needs the bytes of that line and keeping a
workspace's source in memory to answer later would cost tens of megabytes.
References are the exception: they re-lex on demand, which is
[phase6.md](phase6.md#references-are-re-lexed-not-stored)'s reasoning.

THE CLIENT WATCHES THE FILESYSTEM, not the server. File events arrive as
`workspace/didChangeWatchedFiles` after the server registers for them at run
time -- there is no capability for it -- and they are the only thing besides an
open buffer that can change the index between scans. See
[phase9.md](phase9.md).

ONE THREAD READS AND ANSWERS; ONE THREAD SCANS. The message loop handles one
message to completion before reading the next -- the protocol requires
notifications to be applied in order, and every answer depends on the buffer as
the previous message left it. The single exception is the WORKSPACE SCAN, which
runs on a worker thread with an index of its own and is adopted by pointer when
a request needs it; nothing else is shared, and the requests that do not need
cross-file knowledge never wait for it. See
[phase8.md](phase8.md#what-changed).

Phase 7 added three modules beside those and NO new source of truth. Signature
help splits the signature text the parser already recorded; semantic tokens
classify the tokens the document already holds; and the formatter asks the
PARSER for its block depths -- `ParseTokens` takes an optional `IndentTrace` --
rather than deciding for itself which lines open a block. That last one is the
important one: two answers to "does this line open a block" would drift apart,
and the first symptom would be a formatter that indents the whole file after a
single-line `IF`. See [phase7.md](phase7.md#formatting).

## Threading

There is none. One message is read, dispatched and answered before the next is
read. Phase 6 moves analysis onto a worker; the seam is already in place, because
the dispatcher's only shared state is the `Server` object and the handler registry.

## Traps that cost a run

Recorded here because each one fails **silently** — no crash, no error return, a
plausible-looking wrong result.

**yyjson does not copy object keys.** `yyjson_mut_obj_add_sint( doc, obj, "code", n )`
stores the key *pointer*. A FreeBASIC string literal at a call site is a temporary,
so the key dangles and the document serialises as `{"{\"{\\":-32700}` — the value is
right, the key is garbage, and nothing reports an error. Every writer in
`JsonBuilder` therefore goes through `SetNode`, which copies the key with
`yyjson_mut_strncpy`. The `_strcpy` variants copy the *value* only and do not fix
this.

**`STRPTR()` on an empty FreeBASIC string is NULL**, and yyjson reads NULL as
"invalid parameter" rather than "empty". Everything that could receive an empty
string goes through `TextPtr()`, which substitutes a one-byte static.

**A writer buffer belongs to yyjson's heap.** `yyjson_free_buf`, never
`DEALLOCATE`; the wrong one corrupts the process heap. Only `Serialize()` ever
holds such a buffer.

**FreeBASIC cannot resolve a circular by-value return between two types.** An
iterator whose `Value()` returns `JsonValue` cannot be reached from a
`JsonValue.GetIterator()`, in either declaration order: a forward type alias is an
incomplete type and a prototype cannot return one by value (error 71). Hence
`ArrayOf( v )`, which returns a separate `JsonArray` view that owns the iterator
protocol:

```freebasic
for each folder in ArrayOf( params.Member( "workspaceFolders" ) )
```

**`for each` over a TEMPORARY container reads freed memory.**

```freebasic
for each w in FB.Split( SomeText( ), " " )     '' segfault
```

The loop lowers to `dim __it = c.GetIterator( )`, and the temporary the split
returned is destroyed before the body runs, so the iterator walks a freed array.
Bind it to a local first — `dim words as FB.Array( of string ) = FB.Split( ... )`
— and iterate that. It crashes immediately and every time, which is the one
mercy: the equivalent mistake with a borrowed view (`ArrayOf( v )` above) is
safe only because that view owns nothing.

**A container held as a type FIELD must be a named instantiation.** `Items as
FB.Array( of T )` written inline in a field declaration does not instantiate, and
every later member access fails with "Element not defined". `StringArray` and
`WorkspaceFolderArray` in `dispatcher.bi` exist for that reason.

**A parameter may not share a name with a member of its own type.** `RpcError.Code`
and a parameter named `code` collide (error 4), which is why the setter takes
`codeVal`. `name`, `data` and `base` are reserved outright.

**`FB.Map` used to be limited to one compilation unit — fixed upstream, 2026-08-22.**
`fb/hash.bi` defined its `HashOf` overloads without `private`, so a second unit
that included `fb/map.bi` failed to link with ~18 "multiple definition of
FB::HASHOF" errors — naming a standard-library function and neither of the two
files responsible. The overloads are `private` now, as `HashBytes` and `HashInt`
in the same header always were, so a map may be used from any number of modules;
`document_manager.bas` and `dispatcher.bas` both do. A header-only `fb/*.bi`
module needs `private` on every implementation it contains, members included.

**A stray NUL byte in a source file truncates it silently.** fbc stops reading at
the byte, the rest of the file simply does not exist, and the object links with
"undefined reference" errors that name functions plainly visible in the source.
Worth remembering when a build fails that way.

## Position encoding

LSP positions count **UTF-16 code units** unless the client and server agree
otherwise. `utils/position.bas` is the single place where `line + UTF-16 column`
becomes a byte offset into UTF-8 source, and no other module does that arithmetic
— `TextDocument` and every handler call into it.

The rules it implements, and why each one exists, are in
[phase2.md](phase2.md#coordinates): clamping rather than errors, CRLF as one
terminator, mid-surrogate columns rounding down, and malformed UTF-8 counted
rather than rejected.

`Server.PositionEncoding` records the negotiated encoding, which is `utf-16` and
is now stated explicitly in the advertised capabilities. Supporting `utf-8` as
well would mean one more branch inside this module and nowhere else — which is
the point of keeping it here.
