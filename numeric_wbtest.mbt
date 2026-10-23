///|
test "large integers remain exact rather than silently using binary64" {
  let a = numeric(typed_literal("9007199254740993", xsd_namespace()+"integer"), 256)
  let b = numeric(typed_literal("1", xsd_namespace()+"integer"), 256)
  assert_eq(numeric_op("+", a, b, 256).lexical(), "9007199254740994")
  assert_eq(numeric_op("*", a, b, 256).lexical(), "9007199254740993")
  let decimal = numeric(typed_literal("9007199254740993.00", xsd_namespace()+"decimal"), 256)
  assert_eq(a.compare(decimal), Some(0))
}

///|
test "decimal arithmetic uses exact coefficients and explicit division precision" {
  let a = numeric(typed_literal("0.1", xsd_namespace()+"decimal"), 256)
  let b = numeric(typed_literal("0.2", xsd_namespace()+"decimal"), 256)
  assert_eq(numeric_op("+", a, b, 256).lexical(), "0.3")
  assert_eq(numeric_op("/", a, b, 256).lexical(), "0.5")
  assert_eq(numeric_op("/", b, a, 256).lexical(), "2.0")
  let zero = numeric(typed_literal("0", xsd_namespace()+"integer"), 256)
  assert_true(rejects(() => numeric_op("/", a, zero, 256)))
  assert_true(rejects(() => numeric(literal("42"), 256)))
  assert_true(rejects(() => numeric(typed_literal("bad", xsd_namespace()+"integer"), 256)))
  assert_true(rejects(() => numeric_op("*", a, b, 1)))
}
