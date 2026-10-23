///|
test "SPARQL JSON omits unbound variables and preserves term metadata" {
  let r = prepare("SELECT ?x ?y {VALUES ?x {'hello'@en UNDEF}}").execute(sample_data())
  let parsed = @json.parse(r.to_json()[:])
  assert_true(parsed is Json::Object(_))
  assert_true(r.to_json().contains("xml:lang"))
  assert_true(!r.to_json().contains("null"))
  assert_true(r.to_tsv().has_prefix("?x\t?y\n"))
  assert_true(prepare("ASK {}").execute(sample_data()).to_json().contains("true"))
}

///|
test "constructed graph serialization can be loaded by RDF input integration" {
  let r = prepare("CONSTRUCT {?s <urn:copied> ?v} WHERE {?s <urn:cost> ?v}").execute(sample_data())
  assert_eq(Dataset::from_turtle(r.to_ntriples()).size(), 2)
}
