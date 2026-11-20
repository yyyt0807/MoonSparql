///|
test "counted SPARQL regex quantifiers support anchored UUID-shaped matches" {
  assert_eq(
    expression_value("REGEX('AB12','^[a-f]{2}[0-9]{2,3}$','i')"),
    boolean(true),
  )
  assert_eq(
    expression_value("REGEX('AB1234','^[a-f]{2}[0-9]{2,3}$','i')"),
    boolean(false),
  )
  assert_eq(expression_value("REGEX('aaa','^a{2,}$')"), boolean(true))
  assert_eq(expression_value("REGEX('{','^[{]$')"), boolean(true))
}

///|
test "counted regex quantifiers enforce the compile-time expansion bound" {
  let query = prepare("SELECT (REGEX('a','a{257}') AS ?ok) {}")
  let data = Dataset::from_turtle("")
  let rejected = try {
    ignore(query.execute(data))
    false
  } catch {
    Resource(_) => true
    _ => false
  }
  assert_true(rejected)
}
