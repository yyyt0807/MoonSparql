///|
test "prepare preserves forms and graph-pattern operators" {
  let q = prepare("PREFIX e: <urn:> SELECT DISTINCT ?s (COUNT(?x) AS ?n) WHERE {\n" +
    "?s e:p ?x; e:q ?y . OPTIONAL { ?s e:label ?l } FILTER(?x > 0)\n" +
    "{ ?s e:a ?v } UNION { ?s e:b ?v } VALUES ?z {1 2 UNDEF}\n" +
    "BIND(?x + 1 AS ?next) GRAPH ?g {?s e:p ?x} }\n" +
    "GROUP BY ?s HAVING(COUNT(?x)>0) ORDER BY DESC(?n) LIMIT 10 OFFSET 2")
  assert_eq(q.form(), "SELECT")
  assert_true(q.query.distinct)
  assert_eq(q.query.limit, Some(10))
  assert_eq(q.query.offset, 2)
  assert_eq(q.query.group.patterns.length(), 8)
  assert_eq(prepare("ASK {} LIMIT 0").form(), "ASK")
  assert_eq(prepare("CONSTRUCT { _:row <urn:p> ?v } WHERE {?s <urn:p> ?v}").form(), "CONSTRUCT")
}

///|
test "prepare rejects malformed separators unsupported forms and overflow" {
  for query in ["SELECT * {?s <urn:p> ?v ?a <urn:p> ?b}",
    "SELECT ?x ?x {}", "SELECT * {", "ASK {} LIMIT 2147483648",
    "ASK {SERVICE <https://example.org/> {}}", "INSERT DATA {}",
    "ASK {} OFFSET -1", "SELECT REDUCED ?x {}"] {
    assert_true(rejects(() => prepare(query)))
  }
}

///|
test "integer dot terminates triples without becoming a decimal" {
  let q = prepare("SELECT * {?s <urn:p> 1. ?s <urn:q> 2}")
  assert_eq(q.query.group.patterns.length(), 2)
}
