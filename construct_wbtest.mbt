///|
test "constructed RDF is a set and drops unbound or invalid triples" {
  let r = prepare(
    "CONSTRUCT {<urn:all> <urn:kind> ?kind . ?missing <urn:p> ?kind. " +
    "?s ?bad ?kind} WHERE {?s <urn:kind> ?kind BIND('literal' AS ?bad)}",
  ).execute(sample_data())
  assert_eq(r.graph().length(), 1)
  assert_eq(r.graph()[0].subject(), iri("urn:all"))
}

///|
test "CONSTRUCT blank labels are fresh per solution and shared within one" {
  let r = prepare(
    "CONSTRUCT {_:row <urn:subject> ?s; <urn:kind> ?kind} " +
    "WHERE {?s <urn:kind> ?kind} ORDER BY ?s LIMIT 2",
  ).execute(sample_data())
  assert_eq(r.graph().length(), 4)
  assert_eq(r.graph()[0].subject(), r.graph()[1].subject())
  assert_true(r.graph()[0].subject() != r.graph()[2].subject())
  let data = Dataset::from_quads([
    quad(blank("ms_construct_0"), iri("urn:p"), literal("x")),
  ])
  let fresh = prepare("CONSTRUCT {_:x <urn:p> ?s} WHERE {?s <urn:p> ?o}").execute(
    data,
  )
  assert_true(fresh.graph()[0].subject() != blank("ms_construct_0"))
  assert_eq(fresh.graph()[0].object(), blank("ms_construct_0"))
}
