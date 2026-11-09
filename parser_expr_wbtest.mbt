///|
test "expression arithmetic and boolean operators have SPARQL precedence" {
  let p = Parser::new("?n + 2 * 3 > 6 && BOUND(?n)", Limits::default())
  let e = p.expression()
  assert_true(
    e is Binary("&&", Binary(">", Binary("+", _, Binary("*", _, _)), _), _),
  )
  assert_true(p.current() == EndToken)
  let conjunction = Parser::new("?n IN (1,2) && true", Limits::default())
  assert_true(conjunction.expression() is Binary("&&", Call("IN", _), _))
  assert_true(conjunction.current() == EndToken)
}

///|
test "aggregate syntax preserves count-star and distinct intent" {
  let p = Parser::new("COUNT(DISTINCT *) SUM(?n)", Limits::default())
  assert_true(p.expression() is Aggregate("COUNT", None, true, _))
  assert_true(
    p.expression() is Aggregate("SUM", Some(Reference("n")), false, _),
  )
  assert_true(
    rejects(() => Parser::new("UNKNOWN(?n)", Limits::default()).expression()),
  )
  assert_true(
    rejects(() => Parser::new("(?n + )", Limits::default()).expression()),
  )
}

///|
test "IN lists are distinct from grouping parentheses" {
  let p = Parser::new("?n NOT IN (1, 2, 3)", Limits::default())
  assert_true(p.expression() is Unary("!", Call("IN", _)))
  assert_true(p.current() == EndToken)
}
