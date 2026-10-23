# RDF Query Execution

An RDF query relates facts from a dataset and returns bindings or a derived graph.

## Language

**Term**: An RDF IRI, blank node, or literal. Literal identity includes its lexical
value, datatype and optional language tag.
_Avoid_: JSON scalar, node name

**Quad**: One RDF statement with subject, predicate, object and optional named
graph. An absent graph denotes the default graph.

**Dataset**: A set of quads. Repeating a quad does not add another fact.

**Binding**: A partial mapping from query variable names to RDF terms.
_Avoid_: row with nulls

**Solution sequence**: An ordered multiset of bindings. Two equal bindings may
remain distinct occurrences unless the query requests DISTINCT.

**Graph pattern**: A condition that extends or filters bindings using RDF facts.

**Property path**: A relation composed from predicates using inverse, sequence,
alternation or bounded-by-data reachability.

**Query profile**: The explicitly supported language and value semantics of a
release. Unsupported syntax is an error rather than an approximate result.
