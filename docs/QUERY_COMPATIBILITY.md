# SPARQL 1.1 Query Language compatibility

MoonSparql targets complete compatibility with the [W3C SPARQL 1.1 Query Language](https://www.w3.org/TR/sparql11-query/), including its grammar, algebra, evaluation and error semantics over RDF datasets. The target covers all four query forms, solution modifiers, expressions, graph patterns, property paths, subqueries, aggregates, dataset semantics and the query-side SERVICE operator.

## Current delivery for the 0.3.0 development milestone

| Capability | User value and acceptance |
| --- | --- |
| DESCRIBE | Export RDF descriptions for explicit IRIs, variable bindings or DESCRIBE *. The engine collects outgoing statements in the selected default graph and follows blank-node objects. Named graphs can supply bindings. Tests cover cycles, graph isolation, missing resources, unbound variables and output limits. |
| MD5, SHA1, SHA256, SHA384, SHA512 | Compute UTF-8 content fingerprints inside queries. The W3C hash cases and local tests cover standard vectors, Unicode, invalid arguments and resource limits. |
| SELECT REDUCED | Suppress adjacent equal projected bindings before OFFSET and LIMIT, including unbound bindings. The same rule applies in subqueries and preserves the order of surviving rows. |

Run the integration scenario with `moon run examples/query_standard --target wasm-gc --deny-warn`.

SPARQL leaves the description policy to the query service. MoonSparql walks the selected default graph as described above. Work is proportional to selected bindings and candidate postings visited, with space for visited resources and output. Hashing uses linear work and UTF-8 encoding space in input size. REDUCED compares projected terms and holds one preceding binding reference. The existing evaluator still materializes solutions and any required sort.

## Work outstanding on the full compatibility target

| Status | Work |
| --- | --- |
| Partially implemented | Extend regex flags and XPath pattern semantics, datatype conversions and numeric promotion. Close grammar, scope and evaluation differences identified by standard test manifests. |
| Pending implementation | Scoped BNODE allocation, execution-stable NOW, RAND and UUID functions, explicit blank-node labels in query patterns, and query-side SERVICE including variable endpoints and SERVICE SILENT. |
| Pending verification | Cover the remaining applicable positive and negative syntax and evaluation manifests, including the federation tests relevant to SERVICE. Document implementation-defined semantics. |

The current milestone delivers the three additions above and retains existing RDF query, snapshot and result-difference APIs. Full conformance remains a project target and requires the remaining implementation and verification.

SPARQL Update, the HTTP Protocol, Graph Store HTTP Protocol, entailment regimes, persistent storage and endpoint hosting are separate deliverables. The planned query-side SERVICE evaluator belongs to the full query compatibility target.

## MoonTTL linker compatibility

MoonTTL 0.3.0's IRI parser derives `Default` for `IriSpan`. Its span fields
are pairs of integers. When linking with MoonBit `0.10.20+65efd5b93`,
the generated code references the tuple trait implementation, but the
dependency graph can omit `moonbitlang/core/tuple`. Wasm-GC reports
`Key_not_found` for the tuple default symbol. Windows Native may report
an internal `unbound scalar` in the generated `IriSpan` initializer.

The MoonSparql package explicitly imports the standard-library tuple package
so its implementation is linked. This uses the registry version of MoonTTL
without a source patch. The package disables its local unused-import warning
for this link-only dependency. CI builds and tests the four existing backends
with the pinned compiler/core pair.
