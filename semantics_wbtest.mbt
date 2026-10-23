///|
test "projection aliases are visible to later projection expressions" {
  let r = prepare("SELECT (1 AS ?a) (?a+1 AS ?b) {}").execute(sample_data())
  assert_eq(r.rows()[0].get("b"), Some(integer(2)))
}

///|
test "IRI order uses lexical values rather than identity key lengths" {
  let r = prepare("SELECT ?x {VALUES ?x {<urn:z> <urn:aa>}} ORDER BY ?x")
    .execute(sample_data())
  assert_eq(r.rows()[0].get("x"), Some(iri("urn:aa")))
}

///|
test "incompatible literal equality errors symmetrically" {
  let r = prepare("SELECT (!(\"a\"=1) AS ?a) (!(1=\"a\") AS ?b) {}")
    .execute(sample_data())
  assert_eq(r.rows()[0].get("a"), None)
  assert_eq(r.rows()[0].get("b"), None)
}
