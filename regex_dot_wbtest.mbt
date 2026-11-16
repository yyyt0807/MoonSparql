///|
test "SPARQL regex and replacement respect the dot-all flag" {
  assert_eq(expression_value("REGEX('a\\nb','a.b')"), boolean(false))
  assert_eq(expression_value("REGEX('a\\rb','a.b')"), boolean(false))
  assert_eq(expression_value("REGEX('A\\nb','a.b','is')"), boolean(true))
  assert_eq(expression_value("REGEX('a.b','a[.]b')"), boolean(true))
  assert_eq(expression_value("REGEX('.z','[[:digit:].].')"), boolean(true))
  assert_eq(expression_value("REPLACE('a\\nb','a.b','x')"), literal("a\nb"))
  assert_eq(
    expression_value("REPLACE('a\\nb','(a).(b)','$2$1','s')"),
    literal("ba"),
  )
}
