///|
test "dataset is a set while named graphs stay separate" {
  let q = quad(iri("urn:s"), iri("urn:p"), literal("x"))
  let n = quad(iri("urn:s"), iri("urn:p"), literal("x"), graph=iri("urn:g"))
  let input = [q, q, n]
  let data = Dataset::from_quads(input)
  input.clear()
  assert_eq(data.length(), 2)
  assert_eq(data.matching().length(), 1)
  assert_eq(data.matching(graph=iri("urn:g")).length(), 1)
  let copy = data.quads()
  copy.clear()
  assert_eq(data.length(), 2)
  let names = data.graph_names()
  names.clear()
  assert_eq(data.graph_names().length(), 1)
}

///|
test "smallest bound index avoids scanning unrelated facts" {
  let facts = []
  for i = 0; i < 100; i = i + 1 {
    facts.push(quad(iri("urn:s:" + i.to_string()), iri("urn:p"), literal("x")))
  }
  let data = Dataset::from_quads(facts)
  let b = Budget::new({ ..Limits::default(), max_steps: 2, })
  assert_eq(data.scan(Some(iri("urn:s:42")), None, None, None, b).length(), 1)
  assert_eq(b.steps, 1)
  assert_eq(data.matching(predicate=iri("urn:absent")).length(), 0)
}
