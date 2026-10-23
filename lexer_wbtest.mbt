///|
test "lexical tokens distinguish variables paths and comparisons" {
  let ts = lex(
    "SELECT ?x { ?x <urn:p> .5 FILTER(?x<=1e2 && ?x!=2) } #ignored",
    Limits::default(),
  )
  assert_true(ts[0].value == Word("SELECT"))
  assert_true(ts[1].value == Var("x"))
  assert_true(ts[4].value == IriToken("urn:p"))
  assert_true(ts[5].value == NumToken(".5"))
  assert_true(ts.any(t => t.value == Symbol("<=")))
  assert_true(ts.any(t => t.value == Symbol("&&")))
}

///|
test "quoted strings decode escapes and scalar Unicode" {
  let ts = lex("\"a\\n\\u03B1\\U0001F642\" '''long\ntext'''", Limits::default())
  assert_true(ts[0].value == StringToken("a\nα🙂"))
  assert_true(ts[1].value == StringToken("long\ntext"))
  assert_true(rejects(() => lex("\"\\uD800\"", Limits::default())))
  assert_true(rejects(() => lex("\"unfinished", Limits::default())))
  assert_true(rejects(() => lex("1e+", Limits::default())))
}

///|
test "lexing limits fail instead of truncating tokens" {
  assert_true(
    rejects(() => lex("SELECT ?x", { ..Limits::default(), max_tokens: 1, })),
  )
  assert_true(
    rejects(() => lex("12345", { ..Limits::default(), max_query_chars: 4, })),
  )
}
