# Query execution over existing RDF IO

MoonSparql implements a bounded, in-memory SPARQL query profile over a set-valued
RDF dataset and preserves bag semantics in solutions. MoonTTL supplies RDF text
input. We choose this seam instead of another RDF parser or SHACL validator:
existing MoonBit packages already supply those capabilities, while indexed
joins, optional matching and result construction are distinct execution work.

The release does not claim full SPARQL 1.1, persistent database operation,
federation, updates or entailment. Explicit resource limits can reject a query;
silently truncating a successful result would change query meaning.
