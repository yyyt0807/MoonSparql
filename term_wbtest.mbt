///|
test "RDF identity preserves lexical datatypes and normalizes language tags" {
  assert_eq(literal("x"), typed_literal("x", xsd_namespace() + "string"))
  assert_eq(language_literal("hi", "EN-us"), language_literal("hi", "en-US"))
  assert_true(literal("1") != typed_literal("1", xsd_namespace() + "integer"))
  assert_true(typed_literal("1", xsd_namespace() + "integer") !=
    typed_literal("01", xsd_namespace() + "integer"))
  assert_true(iri("urn:a").key() != blank("urn:a").key())
  assert_true(literal("a:1:b").key() != literal("a").key())
}

///|
test "invalid RDF positions and language tags fail explicitly" {
  assert_true(rejects(() => iri("relative")))
  assert_true(rejects(() => iri("urn:has space")))
  assert_true(rejects(() => language_literal("x", "en--US")))
  assert_true(rejects(() => language_literal("x", "1en")))
  assert_true(rejects(() => quad(literal("s"), iri("urn:p"), literal("o"))))
  assert_true(rejects(() => quad(iri("urn:s"), literal("p"), literal("o"))))
  assert_true(rejects(() => quad(iri("urn:s"), iri("urn:p"), literal("o"),
    graph=blank("g"))))
}

///|
test "term formatting escapes literal content without altering identity" {
  assert_eq(literal("a\n\"b").ntriples(), "\"a\\n\\\"b\"")
  assert_eq(language_literal("hello", "en").ntriples(), "\"hello\"@en")
  assert_eq(iri("urn:x").ntriples(), "<urn:x>")
}
