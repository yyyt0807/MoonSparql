///|
test "RDF merge separates blank scopes and retains reference identity and graphs" {
  let p = iri("urn:p")
  let ground = quad(iri("urn:s"), p, literal("v"))
  let left = Dataset::from_quads([quad(blank("x"), p, blank("merge0")), ground])
  let right = Dataset::from_quads([
    quad(blank("x"), p, blank("x"), graph=iri("urn:g")),
    ground,
  ])
  let merged = left.merge_scoped(right)
  assert_eq(merged.length(), 3)
  let q = merged.quads()[2]
  assert_true(q.subject != blank("x") && q.subject != blank("merge0"))
  assert_eq(q.subject, q.object)
  assert_eq(q.graph, Some(iri("urn:g")))
  assert_eq(left.length(), 2)
  assert_eq(
    prepare("SELECT ?s {GRAPH <urn:g> {?s <urn:p> ?s}}")
    .execute(merged)
    .rows()
    .length(),
    1,
  )
  assert_true(
    try {
      ignore(
        left.merge_scoped(right, limits={ ..Limits::default(), max_triples: 3, }),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        left.merge_scoped(right, limits={ ..Limits::default(), max_steps: 1, }),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "SELECT bag union aligns columns without dropping duplicate or unbound rows" {
  let d = Dataset::from_quads([])
  let a = prepare("SELECT ?x {VALUES ?x {1 1 UNDEF}}").execute(d)
  let b = prepare("SELECT ?y {VALUES ?y {2}}").execute(d)
  let joined = a.union_bindings(b)
  assert_eq(joined.variables(), ["x", "y"])
  assert_eq(joined.rows().length(), 4)
  assert_eq(joined.rows()[0].get("x"), joined.rows()[1].get("x"))
  assert_eq(joined.rows()[0].get("y"), None)
  assert_eq(joined.rows()[2].length(), 0)
  assert_eq(joined.rows()[3].get("x"), None)
  assert_eq(joined.rows()[3].get("y").unwrap().lexical(), "2")
  assert_true(
    try {
      ignore(a.union_bindings(prepare("ASK {}").execute(d)))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        a.union_bindings(b, limits={ ..Limits::default(), max_results: 3, }),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(a.union_bindings(b, limits={ ..Limits::default(), max_steps: 1, }))
      false
    } catch {
      _ => true
    },
  )
  let blanks = Dataset::from_quads([
    quad(blank("x"), iri("urn:p"), literal("v")),
  ])
  let r = prepare("SELECT ?s {?s <urn:p> ?o}").execute(blanks)
  let separate = r.union_bindings(r)
  assert_true(separate.rows()[0].get("s") != separate.rows()[1].get("s"))
  assert_eq(
    r.union_bindings(r, shared_blank_scope=true).rows()[0].get("s"),
    r.union_bindings(r, shared_blank_scope=true).rows()[1].get("s"),
  )
}

///|
test "independent catalog blank scopes stay distinct over repeated references" {
  let quads = Array::makei(128, i => {
    quad(
      blank("item" + i.to_string()),
      iri("urn:p"),
      blank("item" + ((i + 1) % 128).to_string()),
    )
  })
  let a = Dataset::from_quads(quads)
  let merged = a.merge_scoped(a)
  assert_eq(merged.length(), 256)
  let names : Map[String, Bool] = Map([])
  for q in merged.quads() {
    names[q.subject.key()] = true
  }
  assert_eq(names.length(), 256)
  for q in merged.quads() {
    assert_true(names.contains(q.object.key()))
  }
}
