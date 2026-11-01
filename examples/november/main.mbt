///|
fn main raise {
  let old = @q.quad(
    @q.iri("urn:asset"),
    @q.iri("urn:owner"),
    @q.literal("Alice"),
  )
  let next = @q.quad(
    @q.iri("urn:asset"),
    @q.iri("urn:owner"),
    @q.literal("Bob"),
  )
  let source = @q.Dataset::from_quads([old])
  let patched = source.apply_patch([old], [next])
  let query = @q.prepare("SELECT ?owner {<urn:asset> <urn:owner> ?owner}")
  let delta = query.execute(source).binding_delta(query.execute(patched))
  assert_eq(delta.removed[0].get("owner").unwrap().lexical(), "Alice")
  assert_eq(delta.added[0].get("owner").unwrap().lexical(), "Bob")
  assert_eq(
    query.execute(source).rows()[0].get("owner").unwrap().lexical(),
    "Alice",
  )
  println(
    "RDF exact patches preserve old snapshots; SELECT bag deltas expose consumer-visible metadata changes",
  )
}
