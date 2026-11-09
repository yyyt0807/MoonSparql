///|
test "intermediate budget fails even when final LIMIT is small" {
  let q = prepare("SELECT * {VALUES ?a {1 2 3} VALUES ?b {1 2 3}} LIMIT 1", limits={
    ..Limits::default(),
    max_bindings: 4,
  })
  assert_true(rejects(() => q.execute(sample_data())))
}

///|
test "failed execution never changes reusable query or dataset" {
  let data = sample_data()
  let before = data.quads()
  let failing = prepare("SELECT * {?s ?p ?o}", limits={
    ..Limits::default(),
    max_steps: 1,
  })
  assert_true(rejects(() => failing.execute(data)))
  assert_eq(data.quads(), before)
  assert_eq(
    prepare("SELECT ?s {?s <urn:owner> ?o}").execute(data).rows().length(),
    1,
  )
}

///|
test "result budget reports failure instead of silent truncation" {
  let query = prepare("SELECT * {?s <urn:kind> ?kind}", limits={
    ..Limits::default(),
    max_results: 1,
  })
  assert_true(rejects(() => query.execute(sample_data())))
  let sliced = prepare("SELECT * {?s <urn:kind> ?kind} LIMIT 1", limits={
    ..Limits::default(),
    max_results: 1,
  })
  assert_eq(sliced.execute(sample_data()).rows().length(), 1)
}

///|
test "unknown features reject during prepare rather than after partial evaluation" {
  for
    text in [
      "SELECT * {SERVICE <urn:server> {}}", "DESCRIBE <urn:s>", "SELECT (NOW() AS ?t) {}",
      "SELECT * {} FROM <urn:remote>", "SELECT * {?s !?p ?o}",
    ] {
    assert_true(rejects(() => prepare(text)))
  }
}
