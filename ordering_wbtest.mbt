///|
test "heterogeneous order comparator is antisymmetric and transitive" {
  let values = [
    None,
    Some(blank("z")),
    Some(iri("urn:z")),
    Some(iri("urn:aa")),
    Some(integer(2)),
    Some(integer(10)),
    Some(literal("3")),
    Some(language_literal("a", "en")),
    Some(typed_literal("NaN", xsd_namespace() + "double")),
    Some(typed_literal("invalid", xsd_namespace() + "integer")),
  ]
  let b = Budget::new(Limits::default())
  for a in values {
    for c in values {
      let ac = order_terms(a, c, b)
      let ca = order_terms(c, a, b)
      assert_true(
        (ac == 0 && ca == 0) || (ac < 0 && ca > 0) || (ac > 0 && ca < 0),
      )
      for d in values {
        if ac <= 0 && order_terms(c, d, b) <= 0 {
          assert_true(order_terms(a, d, b) <= 0)
        }
      }
    }
  }
}
