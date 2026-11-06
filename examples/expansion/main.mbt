///|
fn main raise {
  let p = @q.iri("urn:label")
  let a = @q.Dataset::from_quads([
    @q.quad(@q.blank("item"), p, @q.literal("catalog A")),
  ])
  let b = @q.Dataset::from_quads([
    @q.quad(@q.blank("item"), p, @q.literal("catalog B")),
  ])
  let merged = a.merge_scoped(b)
  let query = @q.prepare("SELECT ?s ?label {?s <urn:label> ?label}")
  let rows = query.execute(merged).rows()
  assert_eq(rows.length(), 2)
  assert_true(rows[0].get("s") != rows[1].get("s"))
  let left = @q.prepare("SELECT ?label {?s <urn:label> ?label}").execute(a)
  let right = @q.prepare("SELECT ?s {?s <urn:label> ?label}").execute(b)
  let union = left.union_bindings(right)
  assert_eq(union.variables(), ["label", "s"])
  assert_eq(union.rows()[0].get("s"), None)
  assert_eq(union.rows()[1].get("label"), None)
  println(
    "RDF catalog merge separates blank scopes; SELECT bag union aligns independent result columns",
  )
}
