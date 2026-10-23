///|
fn sample_data() -> Dataset raise QueryError {
  Dataset::from_quads([
    quad(iri("urn:a"), iri("urn:kind"), iri("urn:Asset")),
    quad(iri("urn:b"), iri("urn:kind"), iri("urn:Asset")),
    quad(iri("urn:a"), iri("urn:owner"), literal("alice")),
    quad(iri("urn:a"), iri("urn:cost"), typed_literal("10", xsd_namespace()+"integer")),
    quad(iri("urn:b"), iri("urn:cost"), typed_literal("20", xsd_namespace()+"integer")),
  ])
}

///|
test "indexed BGP joins bind shared and repeated variables" {
  let data = sample_data()
  let result = prepare("SELECT ?s ?owner {?s <urn:kind> <urn:Asset>. ?s <urn:owner> ?owner}").execute(data)
  assert_eq(result.rows().length(), 1)
  assert_eq(result.rows()[0].get("s"), Some(iri("urn:a")))
  assert_eq(result.rows()[0].get("owner"), Some(literal("alice")))
  assert_eq(prepare("ASK {?s ?p ?s}").execute(data).answer(), Some(false))
  assert_eq(prepare("ASK {}").execute(data).answer(), Some(true))
}

///|
test "projection preserves bag multiplicity and exposes immutable snapshots" {
  let r = prepare("SELECT ?kind {?s <urn:kind> ?kind}").execute(sample_data())
  assert_eq(r.rows().length(), 2)
  let copy = r.rows()
  copy.clear()
  assert_eq(r.rows().length(), 2)
  assert_eq(r.variables(), ["kind"])
  assert_true(rejects(() => prepare("SELECT * {?s ?p ?o}",
    limits={ ..Limits::default(), max_steps: 2 }).execute(sample_data())))
}
