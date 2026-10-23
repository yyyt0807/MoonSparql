# SPARQL execution profile

This release implements an explicit in-memory subset of SPARQL 1.1.
Reference: https://www.w3.org/TR/sparql11-query/ .

## Supported language

- SELECT with explicit variables or expressions, SELECT *, ASK, CONSTRUCT.
- PREFIX, absolute IRIs, variables, explicit literals and language tags.
- Basic graph patterns, predicate/object lists, nested groups, OPTIONAL,
  UNION, MINUS, FILTER, BIND, VALUES with UNDEF, GRAPH with IRI graph names.
- Predicate paths, inverse, sequence, alternatives, zero/one-or-more, zero-or-one.
- DISTINCT, ORDER BY ASC/DESC, OFFSET, LIMIT, GROUP BY expressions and HAVING.
- COUNT (including * and DISTINCT), SUM, AVG, MIN, MAX, SAMPLE.
- Arithmetic + - * /, comparisons, boolean && || !, IN and NOT IN.
- BOUND, STR, LANG, DATATYPE, isIRI/isURI/isBlank/isLiteral/isNumeric, sameTerm,
  STRLEN, CONTAINS, STRSTARTS, STRENDS, LCASE, UCASE, CONCAT, COALESCE, IF,
  LANGMATCHES, STRDT, STRLANG, ABS, CEIL, FLOOR, ROUND.

## Semantics and deliberate restrictions

RDF facts form a set; solutions are bags. Unbound is absence from a binding,
not an RDF null. FILTER expression errors reject that solution. BIND and
projection errors leave their variable unbound. Resource errors propagate.
CONSTRUCT blanks are fresh per solution and graph triples are deduplicated.
Each Dataset is one explicitly scoped RDF dataset; no automatic file merging.

Integer and decimal comparison/addition/subtraction/multiplication are exact.
Decimal division uses 24 fractional digits, half-even rounding. Only xsd:integer,
xsd:decimal and xsd:double participate in numeric promotion; derived integer
datatypes and date/time arithmetic are outside this profile. Group keys and
DISTINCT retain RDF term lexical identity. SUM/AVG/MIN/MAX preserve expression
errors; COUNT removes error values. AVG over an empty group returns integer zero.
SAMPLE chooses the first valid term. No query planner or iteration order promises
a particular SAMPLE when several values are available.

IRI/string order uses Unicode scalar order. ORDER BY adds a deterministic
cross-type order where SPARQL leaves order unspecified: numeric, NaN, boolean,
string, language literal, other typed literal, invalid numeric literal.
This is not a universal RDF canonicalization ordering.

Turtle input uses MoonTTL 0.3.0 and accepts the explicit-term profile exercised
by integration tests. Blank-node property lists and RDF collections are rejected;
TriG, relative IRI resolution, RDF-star and N3 are excluded. For more elaborate
RDF IO, build validated terms/quads through the public programmatic API.
Named graphs are supported by the quad API, not the Turtle loader.
Input character and token budgets are independent of the quad budget.

## Unsupported syntax

No BASE/relative IRIs, query blank labels, FROM/FROM NAMED, SERVICE, UPDATE,
DESCRIBE, REDUCED, SELECT subqueries, EXISTS/NOT EXISTS, negated predicate sets,
GROUP_CONCAT, REGEX, user-defined functions, GROUP BY aliases or inferred facts.
No persistent database, transactions, concurrent mutation or network endpoint.
Group projections must refer to grouped variables, aggregate values or earlier
projection aliases. Unsupported forms fail during preparation or input loading.

## Resource contract

Limits bound input quads, query characters/tokens, AST nesting, execution work,
intermediate bindings, returned rows, property-path pairs and numeric digits.
LIMIT does not bypass evaluation resource checks. Defaults suit small/medium
in-memory datasets. Large path closures or Cartesian joins can still exhaust
budgets; failure is preferable to silently incomplete results.
