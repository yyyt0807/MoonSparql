///|
fn path_data() -> Dataset raise QueryError {
  let p = iri("urn:p")
  Dataset::from_quads([
    quad(iri("urn:a"), p, iri("urn:b")),
    quad(iri("urn:b"), p, iri("urn:a")),
    quad(iri("urn:a"), iri("urn:q"), iri("urn:b")),
  ])
}

///|
test "fixed paths preserve multiplicity while closure terminates on cycles" {
  let p = Predicate(iri("urn:p"))
  let data = path_data()
  let budget = Budget::new(Limits::default())
  assert_eq(
    evaluate_path(data, Alternative(p, p), None, [], budget).length(),
    4,
  )
  assert_eq(evaluate_path(data, Sequence(p, p), None, [], budget).length(), 2)
  assert_eq(evaluate_path(data, OneMore(p), None, [], budget).length(), 4)
  assert_eq(evaluate_path(data, ZeroMore(p), None, [], budget).length(), 4)
}

///|
test "zero-length paths accepted fixed external endpoints only when supplied" {
  let data = path_data()
  let p = ZeroMore(Predicate(iri("urn:absent")))
  let b = Budget::new(Limits::default())
  assert_eq(evaluate_path(data, p, None, [], b).length(), 2)
  assert_eq(evaluate_path(data, p, None, [iri("urn:external")], b).length(), 3)
  assert_true(
    rejects(() => {
      evaluate_path(
        data,
        p,
        None,
        [],
        Budget::new({ ..Limits::default(), max_path_pairs: 1, }),
      )
    }),
  )
}
