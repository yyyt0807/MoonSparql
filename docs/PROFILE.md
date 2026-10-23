# Release profile

The implementation is under development. This file will become the tested
support matrix; it does not claim full SPARQL 1.1 conformance.

The scope is SELECT, ASK and CONSTRUCT over an explicit in-memory RDF dataset,
with basic joins, OPTIONAL, UNION, FILTER, VALUES, BIND, named graphs, paths,
grouping, aggregates, ordering and slicing. Each supported operation requires
positive, negative and boundary tests.

SERVICE, UPDATE, DESCRIBE, remote dataset loading and entailment are outside
this release. No external network request is made while preparing or executing
a query. Runtime resource exhaustion is an error, never a partial-success table.
