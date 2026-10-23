///|
test "ORDER BY sees unprojected values and projection aliases" {
  let r = prepare("SELECT ?s {?s <urn:cost> ?cost} ORDER BY DESC(?cost)").execute(
    sample_data(),
  )
  assert_eq(r.rows()[0].get("s"), Some(iri("urn:b")))
  let aliased = prepare(
    "SELECT (?cost+1 AS ?n) {?s <urn:cost> ?cost} ORDER BY DESC(?n)",
  ).execute(sample_data())
  assert_eq(aliased.rows()[0].get("n").unwrap().lexical(), "21")
}

///|
test "DISTINCT runs before OFFSET LIMIT and does not collapse ordinary bags" {
  let r = prepare(
    "SELECT DISTINCT ?kind {?s <urn:kind> ?kind} OFFSET 1 LIMIT 1",
  ).execute(sample_data())
  assert_eq(r.rows().length(), 0)
  let bag = prepare("SELECT ?kind {?s <urn:kind> ?kind} LIMIT 1 OFFSET 1").execute(
    sample_data(),
  )
  assert_eq(bag.rows().length(), 1)
  assert_eq(
    prepare("ASK {} LIMIT 0").execute(sample_data()).answer(),
    Some(false),
  )
  assert_eq(
    prepare("SELECT * {} LIMIT 0").execute(sample_data()).rows().length(),
    0,
  )
}

///|
test "numeric ordering is value-based and stable" {
  let r = prepare("SELECT ?n {VALUES ?n {10 2 1.0 1}} ORDER BY ?n").execute(
    sample_data(),
  )
  assert_eq(r.rows().map(b => b.get("n").unwrap().lexical()), [
    "1.0", "1", "2", "10",
  ])
}
