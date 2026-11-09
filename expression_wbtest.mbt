///|
fn expression_value(source : String) -> Term raise QueryError {
  Parser::new(source, Limits::default())
  .expression()
  .eval({
    row: Binding::empty(),
    budget: Budget::new(Limits::default()),
    group: None,
    active: {
      data: Dataset::from_quads([]),
      graph: None,
      correlation: None,
      base_uri: None,
    },
  })
}

///|
test "logical error truth tables short circuit in both operand orders" {
  for text in ["false && ?missing", "?missing && false"] {
    assert_eq(expression_value(text), boolean(false))
  }
  for text in ["true || ?missing", "?missing || true"] {
    assert_eq(expression_value(text), boolean(true))
  }
  assert_true(rejects(() => expression_value("true && ?missing")))
  assert_eq(expression_value("IF(true, 1, 1/0)").lexical(), "1")
  assert_eq(expression_value("COALESCE(?missing, 1/0, 42)").lexical(), "42")
}

///|
test "term equality numeric values and sameTerm remain distinct" {
  assert_eq(expression_value("1 = 1.0"), boolean(true))
  assert_eq(expression_value("sameTerm(1, 1.0)"), boolean(false))
  assert_eq(expression_value("1 IN (?missing, 1)"), boolean(true))
  assert_true(rejects(() => expression_value("2 IN (1, ?missing)")))
  assert_eq(expression_value("1+2*3").lexical(), "7")
}

///|
test "string builtins preserve language and count Unicode scalars" {
  assert_eq(
    expression_value("LCASE('HELLO'@EN)"),
    language_literal("hello", "en"),
  )
  assert_eq(expression_value("STRLEN('α🙂')").lexical(), "2")
  assert_eq(
    expression_value("CONCAT('a'@en,'b'@en)"),
    language_literal("ab", "en"),
  )
  assert_eq(expression_value("LANGMATCHES('en-US','en')"), boolean(true))
  assert_true(rejects(() => expression_value("CONTAINS('a','b'@en)")))
  assert_eq(expression_value("ROUND(-1.5)").lexical(), "-1.0")
  assert_eq(expression_value("FLOOR(-1.1)").lexical(), "-2.0")
  assert_eq(expression_value("CEIL(-1.1)").lexical(), "-1.0")
}
