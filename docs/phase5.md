# Phase 5 — completion

## Delivered

| Requirement | Where |
| --- | --- |
| context detection | `src/analysis/completion.tiko` — `CompletionContextAt` |
| candidate collection | `src/analysis/completion.tiko` — `CollectCompletions` |
| `textDocument/completion` | `src/handlers/completion.tiko` |
| capability | `completionProvider { triggerCharacters: [".", ":"], resolveProvider: false }` |

Every item carries `label`, `kind`, `detail`, `documentation`, `insertText`,
`sortText` and `filterText`. `resolveProvider` is **false** because they are
already complete — there is no second round trip to serve.

## Two questions, in order

**1. Where is the cursor?**

| Position | Answer |
| --- | --- |
| after `customer.` | the members of whatever is on the left, *and nothing else* |
| after `customer.Na` | the same, with `Na` as the prefix the client filters on |
| inside a string or a comment | **nothing at all** |
| anywhere else | everything in scope, then the language |

The member case is the one that matters. A list containing `Sub` and `Print`
after `customer.` is worse than an empty one, so a member context never
includes keywords — asserted directly.

**2. What is in scope there?**

Nearest first, because that is the order a person thinks in:

| Group | Contents | `sortText` |
| --- | --- | --- |
| 0 | members, after a dot | `0…` |
| 1 | locals and parameters of the enclosing procedure | `1…` |
| 2 | members of the enclosing type | `2…` |
| 3 | everything else the file declares | `3…` |
| 4 | the 247 reserved words | `4…` |

A client sorts on `sortText`, so the group number is what puts a local above a
keyword when the alphabet would not. `counter` sorts before `sub` on the wire,
and the piped session asserts exactly that.

## The type knowledge behind `customer.`

Three bases resolve:

```freebasic
Colour.      '' the base IS a type, enum or namespace
this.        '' inside a method, the type it belongs to
customer.    '' a variable, whose DECLARED TYPE is looked up
```

The third is the whole of phase 5's type reasoning: the type *name* is read out
of the declaration's detail (`as Customer ptr` → `Customer`) and looked up in
the same file's symbol table. That is not inference — `arr(0).` and
`GetCustomer().` do not resolve, and fall back to offering every member the file
knows. A guess, but a useful one, and still better than offering keywords.

Members defined **out of line** (`sub Customer.SetName`) are parented to the
file rather than to the type, so the member list also collects by dotted name —
without that, half of a real type's methods are missing from its own completion
list.

## Verification

`build\_run_tests.bat`, Windows 11, fbc-modern 1.20.0 (win64), gas64, `-w all`
clean. **699 assertions**, all passing:

| Suite | Assertions |
| --- | --- |
| framing | 41 |
| json + jsonrpc | 110 |
| position | 64 |
| uri + document | 88 |
| analysis | 157 |
| symbols | 74 |
| **completion** | **63** |
| piped session (real process) | 102 |

The completion suite covers context detection at each position (including
inside a string and inside a comment), member completion through a declared
type, through a pointer declaration, through `this.`, of an enum and of a
namespace, the fallback for an unresolvable base, scope completion with its
group ordering, kinds, the case-insensitive de-duplication that keeps a
`declare` and its body from appearing twice, and half-typed input.

The piped session proves it on the wire: a request at an ordinary position
returns 250-odd items in which `counter` is kind 6 with `sortText` `3counter`
and `sub` is kind 14 with `4sub`.

### Performance

Measured on win64/gas64, one full `CollectCompletions` including the keyword
list:

| File | Symbols | Items | Time |
| --- | --- | --- | --- |
| `src/analysis/parser.tiko` | 305 | 292 | 0.60 ms |
| `AfxNova/src/AfxStr.inc` | 423 | 310 | 0.75 ms |
| `fbc/ir-gas64.bas` | 835 | 480 | 1.42 ms |

The first measurement was **4.8 ms**, and the cause was the duplicate check
lower-casing both sides of every comparison — two string allocations per
comparison, 30,000 comparisons. Each item now carries its lower-cased label,
which is an 8× improvement for one field.

### Not verified

- **Linux and macOS**, still.
- **A real editor**, still. The item shape is verified against the wire, which
  is not the same as VS Code drawing a list.
- **Cross-file candidates.** Only this file's declarations are offered; a type
  from an `#include` is invisible. Phase 6.
- **Expression types.** `GetCustomer().` and `arr(0).` fall back to every known
  member rather than resolving.
- **Overloads.** Two procedures of the same name appear once.
- **Snippets.** `insertText` is the plain label — no parameter placeholders,
  and `insertTextFormat` is left at its default.

## Next: phase 6

Workspace analysis: source discovery, a workspace-wide symbol index,
`workspace/symbol`, cross-file definitions and `textDocument/references`. That
index is also what makes completion offer a type declared in another file.
