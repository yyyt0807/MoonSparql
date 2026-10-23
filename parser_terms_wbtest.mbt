///|
test "prefixes expand before matching without changing literal identity" {
  let p = Parser::new("PREFIX ex: <urn:ex:> ex:item \"label\"@EN 42 -2.5", Limits::default())
  p.prefixes()
  assert_eq(p.read_term(), iri("urn:ex:item"))
  assert_eq(p.read_term(), language_literal("label", "en"))
  assert_eq(p.read_term(), typed_literal("42", xsd_namespace() + "integer"))
  assert_eq(p.read_term(), typed_literal("-2.5", xsd_namespace() + "decimal"))
  assert_true(rejects(() => Parser::new("other:item", Limits::default()).read_term()))
}

///|
test "unsupported syntax and depth never become approximate paths" {
  let p = Parser::new("^(<urn:p>/<urn:q>)+|<urn:r>?", Limits::default())
  let path = p.read_path()
  assert_true(path is Alternative(_, _))
  assert_eq(p.current(), EndToken)
  assert_true(rejects(() => Parser::new("_:label", Limits::default()).slot()))
  let template = Parser::new("_:label", Limits::default())
  template.set_template_mode(true)
  assert_eq(template.read_term(), blank("label"))
  assert_true(rejects(() => Parser::new("((((<urn:p>))))",
    { ..Limits::default(), max_depth: 2 }).read_path()))
}
