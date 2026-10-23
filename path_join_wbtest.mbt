///|
test "query paths retain alternative bags and deduplicate closure endpoints" {
  let data = path_data()
  let alternative = prepare("SELECT ?o {<urn:a> (<urn:p>|<urn:q>) ?o}").execute(data)
  assert_eq(alternative.rows().length(), 2)
  let cycle = prepare("SELECT ?o {<urn:a> <urn:p>+ ?o}").execute(data)
  assert_eq(cycle.rows().length(), 2)
  let fixed = prepare("ASK {<urn:external> <urn:p>* <urn:external>}").execute(data)
  assert_eq(fixed.answer(), Some(true))
  assert_eq(prepare("ASK {1 <urn:p>* 1}").execute(data).answer(), Some(true))
}

///|
test "bound endpoint caches do not leak zero-length external nodes to UNDEF" {
  let q = prepare("SELECT ?x ?y {VALUES ?x {<urn:external> UNDEF} ?x <urn:p>* ?y}")
  assert_eq(q.execute(path_data()).rows().length(), 5)
  let reverse = prepare("SELECT ?x {?x ^<urn:p> <urn:a>}").execute(path_data())
  assert_eq(reverse.rows().length(), 1)
  assert_eq(reverse.rows()[0].get("x"), Some(iri("urn:b")))
}
