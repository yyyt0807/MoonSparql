///|
test "bindings are partial maps with compatible joins" {
  let left = Binding::empty()
  assert_true(left.bind(Variable("x"), literal("a")))
  let right = Binding::empty()
  assert_true(right.bind(Variable("y"), literal("b")))
  let joined = left.merge(right).unwrap()
  assert_eq(joined.size(), 2)
  assert_eq(left.size(), 1)
  assert_eq(joined.get("missing"), None)
  assert_true(!right.bind(Variable("y"), literal("wrong")))
  assert_true(right.bind(Variable("x"), literal("wrong")))
  assert_true(left.merge(right) is None)
}

///|
test "binding key distinguishes unbound and lexical delimiters" {
  let a = Binding::empty()
  let b = Binding::empty()
  assert_true(b.bind(Variable("x"), literal("U")))
  assert_true(a.key(["x"]) != b.key(["x"]))
  assert_eq(b.variables(), ["x"])
}
