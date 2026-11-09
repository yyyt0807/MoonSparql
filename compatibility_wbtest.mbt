///|
test "subselect applies its own ordering and slice, and hides unprojected variables" {
  let query = prepare(
    "SELECT * { VALUES ?hidden {99} " +
    "{ SELECT ?x { VALUES (?x ?hidden) {(3 0) (2 1) (2 1) (1 2)} } " +
    "ORDER BY DESC(?x) OFFSET 1 LIMIT 2 } }",
  )
  let result = query.execute(sample_data())
  assert_eq(result.variables().length(), 2)
  assert_true(result.variables().contains("hidden"))
  assert_true(result.variables().contains("x"))
  assert_eq(result.rows().length(), 2)
  for row in result.rows() {
    assert_eq(row.get("x"), Some(integer(2)))
    assert_eq(row.get("hidden"), Some(integer(99)))
  }
}

///|
test "subselect intermediate rows use binding budget instead of final result limit" {
  let query = prepare("SELECT ?x {{SELECT ?x {VALUES ?x {1 2 3}}}} LIMIT 1", limits={
    ..Limits::default(),
    max_results: 1,
  })
  assert_eq(query.execute(sample_data()).rows().length(), 1)
  assert_true(rejects(() => prepare("SELECT * {{ SELECT * FROM <urn:g> {} }}")))
}

///|
test "EXISTS correlates a nested filter and NOT EXISTS does not extend bindings" {
  let data = Dataset::from_turtle("<urn:a> <urn:p> 1 . <urn:b> <urn:p> 2 .")
  let q = prepare(
    "SELECT * {?s <urn:p> ?n FILTER EXISTS { {?z <urn:p> ?m FILTER(?m>?n)} }}",
  ).execute(data)
  assert_eq(q.variables(), ["n", "s"])
  assert_eq(q.rows().length(), 1)
  assert_eq(q.rows()[0].get("s"), Some(iri("urn:a")))
  let negated = prepare(
    "SELECT ?n {?s <urn:p> ?n FILTER NOT EXISTS {?x <urn:p> ?m FILTER(?m>?n)}}",
  ).execute(data)
  assert_eq(negated.rows()[0].get("n"), Some(integer(2)))
}

///|
test "EXISTS substitution respects MINUS domains and projection scopes" {
  let data = Dataset::from_turtle("<urn:a> <urn:p> 1 . <urn:a> <urn:q> 2 .")
  let q = prepare(
    "ASK {VALUES ?s {<urn:a>} FILTER EXISTS {?s <urn:p> ?x MINUS {?s <urn:q> ?y}}}",
  )
  assert_eq(q.execute(data).answer(), Some(true))
  let projected = prepare(
    "ASK {VALUES ?s {<urn:a>} FILTER NOT EXISTS {{SELECT ?s {VALUES ?s {<urn:b>}}}}}",
  )
  assert_eq(projected.execute(data).answer(), Some(true))
}

///|
test "EXISTS and subselect inherit the active named graph" {
  let data = Dataset::from_documents("<urn:s> <urn:p> 0 .", [
    (iri("urn:a"), "<urn:s> <urn:p> 1 ."),
    (iri("urn:b"), "<urn:s> <urn:p> 2 ."),
  ])
  let q = prepare(
    "SELECT ?g ?x { GRAPH ?g { { SELECT ?x {<urn:s> <urn:p> ?x} } " +
    "FILTER EXISTS {<urn:s> <urn:p> 2} } }",
  ).execute(data)
  assert_eq(q.rows().length(), 1)
  assert_eq(q.rows()[0].get("g"), Some(iri("urn:b")))
  assert_eq(q.rows()[0].get("x"), Some(integer(2)))
}

///|
test "negated paths deduplicate endpoints in each direction" {
  let data = Dataset::from_turtle(
    "<urn:a> <urn:p> <urn:b> . <urn:a> <urn:q> <urn:b> . " +
    "<urn:c> <urn:p> <urn:a> . <urn:d> <urn:r> <urn:a> .",
  )
  let q = prepare("SELECT ?o {<urn:a> !(<urn:skip>|^<urn:p>) ?o} ORDER BY ?o").execute(
    data,
  )
  assert_eq(q.rows().length(), 2)
  assert_eq(q.rows()[0].get("o"), Some(iri("urn:b")))
  assert_eq(q.rows()[1].get("o"), Some(iri("urn:d")))
  assert_eq(
    prepare("ASK {<urn:a> !^<urn:r> <urn:c>}").execute(data).answer(),
    Some(true),
  )
  assert_true(rejects(() => prepare("SELECT * {?s ?p/<urn:p> ?o}")))
}

///|
test "dataset clauses merge default triples and preserve empty named graphs" {
  let data = Dataset::from_documents("<urn:original> <urn:p> 0 .", [
    (iri("urn:g1"), "_:same <urn:p> 1 . <urn:s> <urn:p> 5 ."),
    (iri("urn:g2"), "_:same <urn:p> 2 . <urn:s> <urn:p> 5 ."),
    (iri("urn:empty"), ""),
  ])
  let result = prepare(
    "SELECT ?s ?n FROM <urn:g1> FROM <urn:g2> FROM <urn:g1> {?s <urn:p> ?n} ORDER BY ?n",
  ).execute(data)
  assert_eq(result.rows().length(), 3)
  assert_true(result.rows()[0].get("s") != result.rows()[1].get("s"))
  assert_eq(
    prepare("ASK FROM NAMED <urn:g1> {?s ?p ?o}").execute(data).answer(),
    Some(false),
  )
  assert_eq(
    prepare("ASK FROM NAMED <urn:empty> {GRAPH <urn:empty> {}}")
    .execute(data)
    .answer(),
    Some(true),
  )
  assert_eq(
    prepare("ASK FROM <urn:g1> {GRAPH <urn:g1> {}}").execute(data).answer(),
    Some(false),
  )
  assert_true(rejects(() => prepare("ASK FROM <urn:unknown> {}").execute(data)))
  assert_eq(
    prepare("ASK {<urn:original> <urn:p> 0}").execute(data).answer(),
    Some(true),
  )
}

///|
test "relative dataset and pattern IRIs resolve from an explicit query base" {
  let query = prepare(
    "BASE <../repo/> PREFIX e: <ids/> ASK FROM <graph> {e:a <#p> e:b}",
    base_uri="https://example.test/queries/sub/check.rq",
  )
  let data = Dataset::from_documents("", [
    (
      iri("https://example.test/queries/repo/graph"),
      "<https://example.test/queries/repo/ids/a> <https://example.test/queries/repo/#p> <https://example.test/queries/repo/ids/b> .",
    ),
  ])
  assert_eq(query.execute(data).answer(), Some(true))
  assert_true(rejects(() => prepare("ASK {<relative> <urn:p> <urn:o>}")))
}

///|
test "group aliases, DISTINCT concatenation and trailing VALUES compose" {
  let query = prepare(
    "SELECT ?bucket ?tag (COUNT(*) AS ?n) " +
    "(GROUP_CONCAT(DISTINCT ?s;SEPARATOR='|') AS ?labels) " +
    "{VALUES (?v ?s) {(1 'a') (1 'a') (1 'b')}} GROUP BY (?v+1 AS ?bucket) " +
    "HAVING(COUNT(*)=3) VALUES ?tag {'x' 'y'}",
  )
  let result = query.execute(sample_data())
  assert_eq(result.rows().length(), 2)
  for row in result.rows() {
    assert_eq(row.get("bucket"), Some(integer(2)))
    assert_eq(row.get("n"), Some(integer(3)))
    assert_eq(row.get("labels"), Some(literal("a|b")))
  }
  let empty = prepare("SELECT (GROUP_CONCAT(?x) AS ?label) {VALUES ?x {}}").execute(
    sample_data(),
  )
  assert_eq(empty.rows()[0].get("label"), Some(literal("")))
}

///|
test "new string builtins handle Unicode, language, captures and errors" {
  assert_eq(
    expression_value("SUBSTR('α🙂β'@el,2,1)"),
    language_literal("🙂", "el"),
  )
  assert_eq(expression_value("SUBSTR('abc',0,2)"), literal("a"))
  assert_eq(
    expression_value("STRBEFORE('a:b'@en,':')"),
    language_literal("a", "en"),
  )
  assert_eq(expression_value("STRAFTER('a:b'@en,'?')"), literal(""))
  assert_eq(
    expression_value("ENCODE_FOR_URI('a/🙂')"),
    literal("a%2F%F0%9F%99%82"),
  )
  assert_eq(expression_value("REGEX('aBc','^AB','i')"), boolean(true))
  assert_eq(
    expression_value("REPLACE('ab ab','(a)(b)','$2$1')"),
    literal("ba ba"),
  )
  assert_true(rejects(() => expression_value("REPLACE('a','a*','x')")))
  assert_true(rejects(() => expression_value("REGEX('a','a{999999}')")))
}

///|
test "CONSTRUCT WHERE exports the matched subgraph and inspect stays static" {
  let data = Dataset::from_turtle("<urn:a> <urn:p> 1 . <urn:b> <urn:p> 2 .")
  let result = prepare("CONSTRUCT WHERE {?s <urn:p> ?x} ORDER BY ?x LIMIT 1").execute(
    data,
  )
  assert_eq(result.graph().length(), 1)
  assert_eq(result.graph()[0].subject, iri("urn:a"))
  assert_true(rejects(() => prepare("CONSTRUCT WHERE {?s <urn:p>+ ?o}")))
  let profile = prepare(
    "SELECT ?s FROM <urn:g> {{SELECT ?s {?s <urn:p>+ ?o FILTER EXISTS {?o <urn:q> ?z}}}}",
  ).profile()
  assert_eq(profile.variables, ["s"])
  assert_eq(profile.sources, [(iri("urn:g"), false)])
  assert_eq(profile.subqueries, 1)
  assert_eq(profile.property_paths, 1)
  assert_eq(profile.existence_checks, 1)
}

///|
test "anonymous query graph nodes are hidden and do not affect COUNT DISTINCT star" {
  let data = Dataset::from_turtle(
    "<urn:a> <urn:p> <urn:o> . <urn:b> <urn:p> <urn:o> .",
  )
  let result = prepare("SELECT * {[] <urn:p> ?o}").execute(data)
  assert_eq(result.variables(), ["o"])
  assert_eq(result.rows().length(), 2)
  let count = prepare("SELECT (COUNT(DISTINCT *) AS ?n) {[] <urn:p> ?o}").execute(
    data,
  )
  assert_eq(count.rows()[0].get("n"), Some(integer(1)))
}

///|
test "dateTime extraction validates Gregorian ranges and timezone bounds" {
  let suffix = "^^<http://www.w3.org/2001/XMLSchema#dateTime>"
  assert_eq(
    expression_value("DAY('2024-02-29T01:02:03Z'" + suffix + ")"),
    integer(29),
  )
  assert_eq(
    expression_value("SECONDS('2024-02-29T01:02:03.50Z'" + suffix + ")").lexical(),
    "3.5",
  )
  assert_eq(
    expression_value("TZ('2024-02-29T01:02:03'" + suffix + ")"),
    literal(""),
  )
  assert_true(
    rejects(() => expression_value("YEAR('2023-02-29T01:02:03Z'" + suffix + ")")),
  )
  assert_true(
    rejects(() => {
      expression_value("TZ('2024-02-29T01:02:03+14:01'" + suffix + ")")
    }),
  )
}

///|
test "numeric casts truncate, preserve wide integer values and reject invalid lexicals" {
  let integer_iri = "<http://www.w3.org/2001/XMLSchema#integer>"
  assert_eq(expression_value(integer_iri + "(-3.9)"), integer(-3))
  assert_eq(
    expression_value(integer_iri + "(1e20)").lexical(),
    "100000000000000000000",
  )
  assert_true(rejects(() => expression_value(integer_iri + "('2.0')")))
}

///|
test "resource failures in EXISTS and regular expressions propagate through expression fallback" {
  for
    text in [
      "ASK {FILTER EXISTS {VALUES ?x {1 2 3} VALUES ?y {1 2 3}}}", "SELECT (COALESCE(REGEX('abcdefgh','[a-z]+'),false) AS ?v) {}",
    ] {
    let query = prepare(text, limits={ ..Limits::default(), max_steps: 9, })
    let stopped = try {
      ignore(query.execute(sample_data()))
      false
    } catch {
      Resource(_) => true
      e => raise e
    }
    assert_true(stopped)
  }
}

///|
test "a short relative query cannot multiply a large base beyond its preparation budget" {
  let base = "https://example.test/" + Array::make(70, "x").join("") + "/"
  let stopped = try {
    ignore(
      prepare("ASK {<a> <b> <c>}", base_uri=base, limits={
        ..Limits::default(),
        max_query_chars: 180,
      }),
    )
    false
  } catch {
    Resource(_) => true
    e => raise e
  }
  assert_true(stopped)
}
