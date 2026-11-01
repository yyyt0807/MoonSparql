///|
test "dataset patches validate whole snapshot and rebuild query indexes" {
  let s = @moonsparql.iri("urn:item")
  let p = @moonsparql.iri("urn:owner")
  let old = @moonsparql.quad(s, p, @moonsparql.literal("Alice"))
  let next = @moonsparql.quad(s, p, @moonsparql.literal("Bob"))
  let data = @moonsparql.Dataset::from_quads([old])
  let revised = data.apply_patch([old], [next])
  let q = @moonsparql.prepare("SELECT ?o {<urn:item> <urn:owner> ?o}")
  assert_eq(q.execute(data).rows()[0].get("o").unwrap().lexical(), "Alice")
  assert_eq(q.execute(revised).rows()[0].get("o").unwrap().lexical(), "Bob")
  assert_true(
    try {
      ignore(data.apply_patch([next], []))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(data.apply_patch([], [next, next]))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(data.length(), 1)
}

///|
test "SELECT deltas preserve bag counts term identity and unbound values" {
  let data = @moonsparql.Dataset::from_quads([])
  let a = @moonsparql.prepare("SELECT ?x { VALUES ?x {1 1 UNDEF 2} }").execute(
    data,
  )
  let b = @moonsparql.prepare("SELECT ?x { VALUES ?x {1 2 2 UNDEF} }").execute(
    data,
  )
  let delta = a.binding_delta(b)
  assert_eq(delta.retained, 3)
  assert_eq(delta.added.length(), 1)
  assert_eq(delta.removed.length(), 1)
  assert_eq(delta.removed[0].get("x").unwrap().lexical(), "1")
  assert_eq(delta.added[0].get("x").unwrap().lexical(), "2")
  assert_eq(a.binding_delta(a).retained, 4)
  let ask = @moonsparql.prepare("ASK { VALUES ?x {1} }").execute(data)
  assert_true(
    try {
      ignore(a.binding_delta(ask))
      false
    } catch {
      _ => true
    },
  )
  let limits = { ..@moonsparql.Limits::default(), max_results: 1, }
  assert_true(
    try {
      ignore(a.binding_delta(b, limits~))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "patches distinguish named graphs and delta budgets reject full excessive output" {
  let s = @moonsparql.iri("urn:s")
  let p = @moonsparql.iri("urn:p")
  let object = @moonsparql.literal("x")
  let named = @moonsparql.quad(s, p, object, graph=@moonsparql.iri("urn:g"))
  let plain = @moonsparql.quad(s, p, object)
  let source = @moonsparql.Dataset::from_quads([named, plain])
  let revised = source.apply_patch([named], [])
  assert_eq(revised.graph_names().length(), 0)
  assert_eq(revised.length(), 1)
  assert_eq(source.graph_names().length(), 1)
  let a = @moonsparql.prepare("SELECT ?x {VALUES ?x {1 2}}").execute(source)
  let b = @moonsparql.prepare("SELECT ?x {VALUES ?x {3 4}}").execute(source)
  assert_true(
    try {
      ignore(
        a.binding_delta(b, limits={
          ..@moonsparql.Limits::default(),
          max_results: 3,
        }),
      )
      false
    } catch {
      _ => true
    },
  )
}
