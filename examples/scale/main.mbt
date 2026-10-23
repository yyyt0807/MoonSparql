///|
fn main raise {
  let facts = []
  let p = @q.iri("urn:cost")
  for i = 0; i < 10000; i = i + 1 {
    facts.push(@q.quad(@q.iri("urn:item:"+i.to_string()), p,
      @q.typed_literal(i.to_string(), @q.xsd_namespace()+"integer")))
  }
  let data = @q.Dataset::from_quads(facts)
  let lookup = @q.prepare("SELECT ?cost {<urn:item:9999> <urn:cost> ?cost}").execute(data)
  assert_eq(lookup.rows().length(), 1)
  assert_true(lookup.statistics().steps < 10)
  let result = @q.prepare("SELECT (COUNT(*) AS ?count) (SUM(?v) AS ?total) {?s <urn:cost> ?v}")
    .execute(data)
  assert_eq(result.rows()[0].get("count").unwrap().lexical(), "10000")
  assert_eq(result.rows()[0].get("total").unwrap().lexical(), "49995000")
  println("10000 facts: indexed lookup and exact sum verified")
  println(result.to_json())
}
