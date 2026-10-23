///|
test "implicit aggregation creates one group even when no rows match" {
  let q = prepare(
    "SELECT (COUNT(*) AS ?n) (SUM(?v) AS ?s) (AVG(?v) AS ?a) {?subject <urn:absent> ?v}",
  )
  let r = q.execute(sample_data())
  assert_eq(r.rows().length(), 1)
  assert_eq(r.rows()[0].get("n"), Some(integer(0)))
  assert_eq(r.rows()[0].get("s"), Some(integer(0)))
  assert_eq(r.rows()[0].get("a"), Some(integer(0)))
}

///|
test "grouping having ordering and arithmetic aggregates compose" {
  let q = prepare(
    "SELECT ?kind (SUM(?cost) AS ?sum) (AVG(?cost) AS ?avg) " +
    "(MAX(?cost)-MIN(?cost) AS ?spread) {?s <urn:kind> ?kind; <urn:cost> ?cost} " +
    "GROUP BY ?kind HAVING(COUNT(*)>1) ORDER BY DESC(?sum)",
  )
  let r = q.execute(sample_data())
  assert_eq(r.rows().length(), 1)
  let row = r.rows()[0]
  assert_eq(row.get("sum"), Some(integer(30)))
  assert_eq(row.get("avg").unwrap().lexical(), "15.0")
  assert_eq(row.get("spread"), Some(integer(10)))
}

///|
test "aggregate DISTINCT counts terms while COUNT skips unbound" {
  let r = prepare(
    "SELECT (COUNT(?x) AS ?all) (COUNT(DISTINCT ?x) AS ?unique) " +
    "(COUNT(DISTINCT *) AS ?rows) {VALUES ?x {1 1 1.0 UNDEF}}",
  ).execute(sample_data())
  assert_eq(r.rows()[0].get("all"), Some(integer(3)))
  assert_eq(r.rows()[0].get("unique"), Some(integer(2)))
  assert_eq(r.rows()[0].get("rows"), Some(integer(3)))
  let grouped = prepare(
    "SELECT ?x (COUNT(*) AS ?n) {VALUES ?x {1 1.0}} GROUP BY ?x",
  ).execute(sample_data())
  assert_eq(grouped.rows().length(), 2)
}

///|
test "aggregate errors leave their column unbound without deleting COUNT" {
  let r = prepare(
    "SELECT (COUNT(?x) AS ?n) (SUM(?x) AS ?s) (AVG(?x) AS ?a) " +
    "(MIN(?x) AS ?m) {VALUES ?x {1 UNDEF 2}}",
  ).execute(sample_data())
  assert_eq(r.rows().length(), 1)
  assert_eq(r.rows()[0].get("n"), Some(integer(2)))
  assert_eq(r.rows()[0].get("s"), None)
  assert_eq(r.rows()[0].get("a"), None)
  assert_eq(r.rows()[0].get("m"), None)
}
