///|
test "optional joins retain unmatched rows and filter on merged bindings" {
  let data = sample_data()
  let r = prepare(
    "SELECT ?s ?owner {?s <urn:kind> <urn:Asset> OPTIONAL {?s <urn:owner> ?owner}}",
  ).execute(data)
  assert_eq(r.rows().length(), 2)
  assert_eq(r.rows()[1].get("owner"), None)
  let threshold = prepare(
    "SELECT ?s ?owner {?s <urn:cost> ?cost OPTIONAL {" +
    "?s <urn:owner> ?owner FILTER(?cost>15)}}",
  ).execute(data)
  assert_eq(threshold.rows().length(), 2)
  assert_eq(threshold.rows()[0].get("owner"), None)
}

///|
test "group filters can precede bindings but nested groups do not capture them" {
  let r = prepare("SELECT ?s {FILTER(?cost>15) ?s <urn:cost> ?cost}").execute(
    sample_data(),
  )
  assert_eq(r.rows().length(), 1)
  assert_eq(r.rows()[0].get("s"), Some(iri("urn:b")))
  let nested = prepare("SELECT * {?s <urn:cost> ?cost {FILTER(?cost>15)}}").execute(
    sample_data(),
  )
  assert_eq(nested.rows().length(), 0)
}

///|
test "BIND extends without discarding rows on expression errors" {
  let r = prepare(
    "SELECT ?s ?next ?failed {?s <urn:cost> ?cost " +
    "BIND(?cost+1 AS ?next) BIND(1/0 AS ?failed)}",
  ).execute(sample_data())
  assert_eq(r.rows().length(), 2)
  assert_eq(r.rows()[0].get("next").unwrap().lexical(), "11")
  assert_eq(r.rows()[0].get("failed"), None)
  assert_eq(
    prepare("SELECT * {FILTER(1/0>1)}").execute(sample_data()).rows().length(),
    0,
  )
}
