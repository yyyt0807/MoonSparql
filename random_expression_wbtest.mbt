///|
test "RAND produces a fresh double below one with an injected entropy source" {
  let query = prepare("SELECT (RAND() AS ?n) { VALUES ?x { 1 2 } }")
  let data = Dataset::from_turtle("")
  let n = Ref(0)
  let generated = query
    .execute(
      data,
      entropy=Some(() => {
        n.val += 1
        if n.val == 1 {
          0UL
        } else {
          18446744073709551615UL
        }
      }),
    )
    .rows()
  assert_eq(n.val, 2)
  assert_eq(generated[0].get("n"), Some(Floating(0.0).term(32)))
  assert_eq(generated[1].get("n"), Some(Floating(0.9999999999999999).term(32)))
  assert_eq(query.execute(data).rows()[0].get("n"), None)
}
