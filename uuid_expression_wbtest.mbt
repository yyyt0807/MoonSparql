///|
test "UUID inserts version and variant bits and rejects repeated random input" {
  let query = prepare("SELECT (UUID() AS ?id) { VALUES ?x { 1 2 } }")
  let data = Dataset::from_turtle("")
  let rows = query.execute(data, entropy=Some(() => 0UL)).rows()
  assert_eq(
    rows[0].get("id"),
    Some(iri("urn:uuid:00000000-0000-4000-8000-000000000000")),
  )
  assert_eq(rows[1].get("id"), None)
}
