///|
test "MoonTTL integrates Unicode lexical values and datatype identity" {
  let data = Dataset::from_turtle(
    "@prefix e: <urn:example:> .\ne:a e:label \"α🙂\"@EN .\ne:a e:n 42 .",
  )
  assert_eq(data.length(), 2)
  let r = prepare(
    "SELECT ?n ?label {<urn:example:a> <urn:example:n> ?n; <urn:example:label> ?label}",
  ).execute(data)
  assert_eq(r.rows().length(), 1)
  assert_eq(r.rows()[0].get("n"), Some(integer(42)))
  assert_eq(r.rows()[0].get("label"), Some(language_literal("α🙂", "en")))
}

///|
test "RDF integration rejects unsupported anonymous nodes and malformed data" {
  assert_true(rejects(() => Dataset::from_turtle("[] <urn:p> <urn:o> .")))
  assert_true(rejects(() => Dataset::from_turtle("<urn:s> <urn:p> (1 2) .")))
  assert_true(
    rejects(() => Dataset::from_turtle("<urn:s> <urn:p> \"unterminated")),
  )
}
