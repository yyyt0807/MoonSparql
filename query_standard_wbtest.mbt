///|
test "DESCRIBE follows blank-node cycles only in the selected default graph" {
  let root = iri("urn:root")
  let detail = blank("detail")
  let link = iri("urn:link")
  let label = iri("urn:label")
  let graph = iri("urn:source")
  let data = Dataset::from_quads([
    quad(root, link, detail, graph~),
    quad(detail, link, detail, graph~),
    quad(detail, label, literal("detail"), graph~),
    quad(root, label, literal("other graph")),
  ])
  let fixed = prepare("PREFIX e: <urn:> DESCRIBE e:root e:root FROM e:source")
  let result = fixed.execute(data)
  assert_eq(fixed.form(), "DESCRIBE")
  assert_eq(result.graph().length(), 3)
  assert_true(result.graph().all(q => q.graph is None))
  assert_false(result.to_ntriples().contains("other graph"))
  let all = prepare("DESCRIBE * FROM <urn:source> { ?x <urn:label> ?y }")
  assert_eq(all.execute(data).graph().length(), 2)
  let bound = prepare(
    "DESCRIBE ?x FROM <urn:source> WHERE { VALUES ?x { <urn:root> UNDEF 'literal' } } LIMIT 1",
  )
  assert_eq(bound.execute(data).graph().length(), 3)
  let empty = prepare("DESCRIBE ?x WHERE { ?x <urn:missing> ?value }").execute(
    data,
  )
  assert_true(empty.graph().is_empty())
  assert_true(empty.variables().is_empty())
  let rows = prepare("SELECT ?x {}").execute(data)
  assert_true(rejects(() => empty.binding_delta(rows)))
  assert_true(rejects(() => empty.union_bindings(rows)))
}

///|
test "DESCRIBE rejects malformed targets and enforces the graph output limit" {
  for
    source in [
      "DESCRIBE", "DESCRIBE * ?x {}", "DESCRIBE 1", "DESCRIBE <urn:root> WHERE",
    ] {
    assert_true(rejects(() => prepare(source)))
  }
  let data = Dataset::from_turtle("<urn:s> <urn:p> 1, 2 .")
  let query = prepare("DESCRIBE <urn:s>", limits={
    ..Limits::default(),
    max_results: 1,
  })
  assert_true(
    (Ok(query.execute(data)) catch { e => Err(e) })
    is Err(Resource("description triples")),
  )
}

///|
test "SELECT REDUCED removes adjacent projected duplicates before slicing" {
  let data = Dataset::from_quads([])
  let ordered = prepare(
    "SELECT REDUCED ?x { VALUES (?x ?k) { (1 1) (1 2) (2 3) (1 4) } } " +
    "ORDER BY ?k OFFSET 1 LIMIT 2",
  )
  let rows = ordered.execute(data).rows()
  assert_eq(rows.map(row => row.get("x")), [Some(integer(2)), Some(integer(1))])
  let nested = prepare(
    "SELECT * { { SELECT REDUCED ?x { VALUES ?x { UNDEF UNDEF 1 1 } } } }",
  )
  assert_eq(nested.execute(data).rows().length(), 2)
  assert_eq(nested.execute(data).rows()[0].get("x"), None)
}

///|
test "hashes use UTF-8 and lowercase hexadecimal" {
  let data = Dataset::from_quads([])
  let source = "SELECT (MD5('é') AS ?md5) (SHA1('é') AS ?sha1) " +
    "(SHA256('é') AS ?sha256) (SHA384('é') AS ?sha384) (SHA512('é') AS ?sha512) {}"
  let row = prepare(source).execute(data).rows()[0]
  assert_eq(row.get("md5"), Some(literal("66ddcd97cfdeabb2f6fb8a999b4bc76f")))
  assert_eq(
    row.get("sha1"),
    Some(literal("bf15be717ac1b080b4f1c456692825891ff5073d")),
  )
  assert_eq(
    row.get("sha256"),
    Some(
      literal(
        "4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c",
      ),
    ),
  )
  assert_eq(
    row.get("sha384"),
    Some(
      literal(
        "41a2ddb34dca0b400fa9b73a368307acbed758e85ce50527d1655a263a10e20eefa18f8116767a128877a97c11160a26",
      ),
    ),
  )
  assert_eq(
    row.get("sha512"),
    Some(
      literal(
        "9e2ad28633f24451bd4f3c1cb20586a21a44c3aeedbdc01b9cc8fa72917ea7bd689c82b8bf1fef89b911cf8cc46fa2c1ccc10087b2094fd4d3350ecd88526a2c",
      ),
    ),
  )
}

///|
test "hashes validate arity and type while propagating resource exhaustion" {
  assert_true(rejects(() => prepare("SELECT (SHA1() AS ?h) {}")))
  assert_true(rejects(() => prepare("SELECT (MD5('a', 'b') AS ?h) {}")))
  let data = Dataset::from_quads([])
  let query = prepare(
    "PREFIX xsd: <http://www.w3.org/2001/XMLSchema#> " +
    "SELECT (MD5(''^^xsd:string) AS ?empty) (SHA1('a'@en) AS ?lang) " +
    "(SHA256(2) AS ?number) (SHA512(?missing) AS ?unbound) {}",
  )
  let row = query.execute(data).rows()[0]
  assert_eq(row.get("empty"), Some(literal("d41d8cd98f00b204e9800998ecf8427e")))
  assert_eq(row.get("lang"), None)
  assert_eq(row.get("number"), None)
  assert_eq(row.get("unbound"), None)
  let limited = prepare("SELECT (SHA256('long input') AS ?hash) {}", limits={
    ..Limits::default(),
    max_steps: 8,
  })
  assert_true(
    (Ok(limited.execute(data)) catch { e => Err(e) }) is Err(Resource(_)),
  )
}
