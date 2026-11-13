# SPARQL execution profile

This profile describes the in-memory implementation in the current source.
The target is full compatibility with the [SPARQL 1.1 Query Recommendation](https://www.w3.org/TR/sparql11-query/).
See [current delivery and outstanding work](QUERY_COMPATIBILITY.md).

## Supported language

- SELECT with explicit variables or expressions, SELECT *, ASK, CONSTRUCT
  with a template, CONSTRUCT WHERE with a triple-only pattern, and DESCRIBE with IRIs, variables or `*`.
- PREFIX and BASE, absolute and base-relative IRIs, explicit literals and
  language tags. An embedding application may pass `prepare(base_uri=...)`.
- Basic graph patterns, predicate/object lists, nested groups, OPTIONAL,
  UNION, MINUS, FILTER, BIND, inline and trailing VALUES with UNDEF, and GRAPH.
- Anonymous nodes, blank-node property lists and RDF collections in query
  triples and CONSTRUCT templates. Anonymous query variables are hidden from
  projection and COUNT(DISTINCT *).
- SELECT subqueries have their own projection, grouping, ordering and slice.
  Outer groups join the projected bindings as a bag in the current active graph.
- EXISTS and NOT EXISTS use the active graph and the outer solution bindings.
  Inner bindings remain scoped to the existence test.
- Predicate paths, inverse, sequence, alternatives, zero/one-or-more,
  zero-or-one, and negated property sets with forward and reverse members.
- DISTINCT, REDUCED, ORDER BY ASC/DESC, OFFSET, LIMIT, GROUP BY expressions and aliases,
  and HAVING. Trailing VALUES joins after grouping and HAVING.
- COUNT (including * and DISTINCT), SUM, AVG, MIN, MAX, SAMPLE and GROUP_CONCAT
  with DISTINCT and an optional SEPARATOR. Concatenation order is unspecified.
- Arithmetic + - * /, comparisons, boolean && || !, IN and NOT IN.
- BOUND, STR, LANG, DATATYPE, isIRI/isURI/isBlank/isLiteral/isNumeric, sameTerm,
  STRLEN, CONTAINS, STRSTARTS, STRENDS, LCASE, UCASE, CONCAT, COALESCE, IF,
  LANGMATCHES, STRDT, STRLANG, ABS, CEIL, FLOOR, ROUND.
- SUBSTR, STRBEFORE, STRAFTER, ENCODE_FOR_URI, REGEX and REPLACE.
- MD5, SHA1, SHA256, SHA384 and SHA512 over the UTF-8 lexical form of an untagged string. Results are lowercase hexadecimal strings.
- IRI and URI use the query base for relative string values. Recognized
  datatype conversion functions are `xsd:integer` and `xsd:double`.
- YEAR, MONTH, DAY, HOURS, MINUTES, SECONDS, TIMEZONE and TZ on xsd:dateTime.
  The lexical profile covers years 0001–9999, hours 00–23, fractional seconds
  and absent, Z or signed offsets up to 14:00.

## Semantics and deliberate restrictions

RDF facts form a set; solutions are bags. Unbound is absence from a binding,
not an RDF null. FILTER expression errors reject that solution. BIND and
projection errors leave their variable unbound. Resource errors propagate.
CONSTRUCT template blanks are fresh per solution. Graph triples are deduplicated.
DESCRIBE follows the graph policy in [Query compatibility](QUERY_COMPATIBILITY.md).
REDUCED compares adjacent projected bindings before OFFSET and LIMIT.
Fixed sequence and alternative paths preserve bag multiplicity. Repetition
deduplicates reachable endpoints. Negated property sets deduplicate endpoints
within each direction. For zero-length variable-to-variable paths the identity
pairs come from nodes of the active graph. A constant endpoint may match itself
even when it is absent from that graph.

Integer and decimal comparison/addition/subtraction/multiplication are exact.
Decimal division uses 24 fractional digits, half-even rounding. Only xsd:integer,
xsd:decimal and xsd:double participate in numeric promotion; derived integer
datatypes and date/time arithmetic are outside this profile. Group keys and
DISTINCT retain RDF term lexical identity. SUM/AVG/MIN/MAX preserve expression
errors; COUNT removes error values. AVG over an empty group returns integer zero.
SAMPLE chooses the first valid term in evaluation order.

REGEX and REPLACE use the MoonBit core automata engine. Supported flags are
empty and `i`. Patterns are limited to 256 UTF-16 units. Counted repetition,
XPath-specific class subtraction and flags `m`, `s`, `x` are outside the
profile. REPLACE supports numbered captures, escaped dollar and backslash, and
rejects empty matches. Expression errors leave the output unbound or reject the
filter row. The execution budget also charges input/pattern work and replacement
output.

IRI/string order uses Unicode scalar order. ORDER BY adds a deterministic
cross-type order where SPARQL leaves order unspecified: numeric, NaN, boolean,
string, language literal, other typed literal, invalid numeric literal.
This is not a universal RDF canonicalization ordering.

## Dataset sources and file input

A supplied Dataset has one default graph and separately identified named graphs.
Queries without dataset clauses use that snapshot. FROM merges selected local
named sources into the default graph and scopes blank nodes separately per
source. FROM NAMED retains the selected sources under their graph IRIs. A
FROM NAMED-only query has an empty default graph. Repeated clauses for the same
source and role are deduplicated. A missing source raises an input error.
Source IRIs are local lookup keys. They are never fetched by the query engine.

`Dataset::from_documents` assembles independently scoped Turtle documents.
`Dataset::from_quads(named_graphs=...)` can register an empty named graph.
The CLI accepts a JSON catalogue through `--dataset`. Fields are optional
and must use these types.

| Field | Meaning |
| --- | --- |
| `base` | Absolute query base IRI for resolving relative references |
| `default` | Default graph Turtle text |
| `named` | Object mapping graph IRIs to Turtle text |
| `sources` | Additional IRI-to-Turtle map for FROM and FROM NAMED |

With no dataset clause, `sources` is absent from the active dataset. With
clauses, `named` and `sources` form the catalogue and their IRI keys must be
disjoint. Text and quad totals are bounded across all loaded documents.

Turtle input uses MoonTTL 0.3.0 with explicit terms. Source text using blank-node
property lists, RDF collections, TriG, RDF-star or N3 is outside the input
profile. Query-side collection syntax is independent of RDF loading. Applications
with other RDF readers can pass validated terms and quads to the library.
Input character and token budgets are independent of the quad budget.

## Unsupported syntax

Unsupported query forms and functions include SERVICE, UPDATE, explicit `_:` labels in query patterns, BNODE(), NOW(), RAND(), UUID(), STRUUID(), unlisted casts and user-defined functions.
EXISTS with a BIND target that is already correlated is rejected. Subqueries
cannot declare their own dataset. Correlation to a nested SELECT matches its
projected variables after the subquery executes.
Persistent storage, inferred facts and network endpoints are outside the scope.
Group projections must refer to grouped variables, aggregate values or earlier
projection aliases. Unsupported forms fail during preparation or input loading.

## Resource contract

Limits bound input quads, query characters/tokens, expanded IRI text, AST nesting, execution work,
intermediate bindings, returned rows, property-path pairs and numeric digits.
LIMIT does not bypass evaluation resource checks. Defaults suit small/medium
in-memory datasets. Large closures, repeated EXISTS evaluations and Cartesian
joins can exhaust a budget. Resource failures propagate to the caller.

## W3C compatibility checks

The runner uses the [W3C RDF test suite](https://w3c.github.io/rdf-tests/sparql/)
at revision `202a74eb81f47bcad13bbafdd37eba69c361c1c2`. It executes the official
query files against the Native CLI. RDFLib loads the manifests and serializes
RDF fixtures to explicit triple documents. Expected SPARQL XML/JSON and RDF
result sets are checked for row multiplicity, declared order and consistent
blank-node identity. Numeric and Boolean lexical variants compare by value
within their datatype. CONSTRUCT graphs compare by RDF isomorphism.

| W3C query evaluation category | Passed | Executed |
| --- | ---: | ---: |
| Subquery | 16 | 16 |
| EXISTS | 6 | 6 |
| Negation | 12 | 12 |
| Property path | 33 | 33 |
| Built-in functions | 69 | 76 |
| Aggregates | 42 | 42 |
| Grouping | 4 | 4 |
| Bindings | 30 | 30 |
| CONSTRUCT | 5 | 5 |
| Dataset (SPARQL 1.0, shared query semantics) | 12 | 12 |
| Total | 229 | 236 |

The seven unsupported-function cases are executed and recorded by exact case ID
in [the compatibility baseline](../scripts/w3c_known_gaps.json). CI fails on
other failures, a change in an expected failure kind or an unexpected pass.
Coverage applies to the listed query evaluation manifests. The full syntax,
protocol, update, federation and entailment suites are outside this check.

```sh
moon build --target native --deny-warn
python -m pip install -r scripts/requirements-interop.txt
python scripts/check_w3c.py _build/native/debug/build/cmd/main/main.exe --fetch
```

The checkout and per-case results go under `_build`. The fixtures remain in
the W3C checkout under its upstream license.
