///|
test "STRUUID returns a plain lexical UUID with no URN prefix" {
  let query = prepare("SELECT (STRUUID() AS ?id) {}")
  let data = Dataset::from_turtle("")
  let rows = query.execute(data, entropy=Some(() => 0UL)).rows()
  assert_eq(
    rows[0].get("id"),
    Some(literal("00000000-0000-4000-8000-000000000000")),
  )
}
