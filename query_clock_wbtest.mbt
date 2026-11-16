///|
test "NOW uses one host clock across rows and subqueries and resets per execution" {
  let query = prepare(
    "SELECT (NOW() AS ?outer) ?inner { VALUES ?x { 1 2 } { SELECT (NOW() AS ?inner) {} } }",
  )
  let data = Dataset::from_turtle("")
  let first = query.execute(data, now=Some("2026-11-16T08:30:00Z"))
  assert_eq(first.bindings.length(), 2)
  for row in first.bindings {
    assert_eq(row.get("outer"), row.get("inner"))
    assert_eq(
      row.get("outer"),
      Some(typed_literal("2026-11-16T08:30:00Z", xsd_namespace() + "dateTime")),
    )
  }
  let second = query.execute(data, now=Some("2026-11-16T08:31:00Z"))
  assert_true(first.bindings[0].get("outer") != second.bindings[0].get("outer"))
  assert_eq(query.execute(data).bindings[0].get("outer"), None)
  assert_true(
    try {
      ignore(query.execute(data, now=Some("2026-02-30T12:00:00Z")))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(prepare("SELECT (NOW(1) AS ?t) {}"))
      false
    } catch {
      _ => true
    },
  )
}
