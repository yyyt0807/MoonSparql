///|
test "UNION and VALUES preserve duplicate solutions and UNDEF compatibility" {
  let r = prepare("SELECT ?s {{?s <urn:owner> ?o} UNION {?s <urn:owner> ?o}}").execute(
    sample_data(),
  )
  assert_eq(r.rows().length(), 2)
  let values = prepare("SELECT ?s ?v {?s <urn:owner> ?o VALUES ?v {1 1 UNDEF}}").execute(
    sample_data(),
  )
  assert_eq(values.rows().length(), 3)
  assert_eq(values.rows()[2].get("v"), None)
  let conflict = prepare("SELECT * {VALUES (?x ?y) {(1 2)} VALUES ?x {3}}").execute(
    sample_data(),
  )
  assert_eq(conflict.rows().length(), 0)
}

///|
test "MINUS requires shared variables as well as compatible values" {
  let shared = prepare(
    "SELECT ?s {?s <urn:kind> <urn:Asset> MINUS {?s <urn:owner> ?o}}",
  ).execute(sample_data())
  assert_eq(shared.rows().length(), 1)
  assert_eq(shared.rows()[0].get("s"), Some(iri("urn:b")))
  let disjoint = prepare(
    "SELECT ?s {?s <urn:kind> <urn:Asset> MINUS {?x <urn:owner> ?o}}",
  ).execute(sample_data())
  assert_eq(disjoint.rows().length(), 2)
  assert_eq(
    prepare("SELECT * {VALUES ?x {1} MINUS {}}")
    .execute(sample_data())
    .rows()
    .length(),
    1,
  )
}

///|
test "named graph queries do not leak facts from the default graph" {
  let data = Dataset::from_quads([
    quad(iri("urn:s"), iri("urn:p"), literal("default")),
    quad(iri("urn:s"), iri("urn:p"), literal("named"), graph=iri("urn:g")),
  ])
  let r = prepare("SELECT ?g ?v {GRAPH ?g {?s <urn:p> ?v}}").execute(data)
  assert_eq(r.rows().length(), 1)
  assert_eq(r.rows()[0].get("g"), Some(iri("urn:g")))
  assert_eq(r.rows()[0].get("v"), Some(literal("named")))
  let d = prepare("SELECT ?v {?s <urn:p> ?v}").execute(data)
  assert_eq(d.rows()[0].get("v"), Some(literal("default")))
}
