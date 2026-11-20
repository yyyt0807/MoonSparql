///|
test "BNODE makes distinct nodes and skips existing dataset labels" {
  let query = prepare(
    "SELECT (BNODE() AS ?a) (BNODE() AS ?b) { VALUES ?x { 1 2 } }",
  )
  let data = Dataset::from_quads([
    quad(blank("ms_query_0"), iri("urn:p"), literal("x")),
  ])
  let rows = query.execute(data).rows()
  assert_eq(rows[0].get("a"), Some(blank("ms_query_1")))
  assert_true(rows[0].get("a") != rows[0].get("b"))
  assert_true(rows[0].get("b") != rows[1].get("a"))
}
