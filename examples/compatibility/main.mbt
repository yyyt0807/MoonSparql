///|
fn main raise {
  let releases = @q.iri("urn:catalog:releases")
  let advisories = @q.iri("urn:catalog:advisories")
  let dataset = @q.Dataset::from_documents("", [
    (
      releases,
      "<urn:component:a> <urn:version> '2.1' ; <urn:category> 'runtime' . " +
      "<urn:component:b> <urn:version> '1.4' ; <urn:category> 'runtime' .",
    ),
    (advisories, "<urn:component:b> <urn:advisory> <urn:finding:1> ."),
  ])
  let eligible = @q.prepare(
    "SELECT ?category (GROUP_CONCAT(?version) AS ?eligible) " +
    "FROM <urn:catalog:releases> FROM NAMED <urn:catalog:advisories> { " +
    "{SELECT ?component ?category ?version {?component <urn:version> ?version ; <urn:category> ?category}} " +
    "FILTER NOT EXISTS { GRAPH <urn:catalog:advisories> {?component <urn:advisory> ?finding} } " +
    "} GROUP BY ?category",
  )
  let result = eligible.execute(dataset)
  let rows = result.rows()
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].get("eligible"), Some(@q.literal("2.1")))
  println(eligible.profile().to_json())
  println(result.to_tsv())

  let view = @q.prepare(
    "CONSTRUCT FROM <urn:catalog:releases> WHERE {?component <urn:version> ?version}",
  ).execute(dataset)
  assert_eq(view.graph().length(), 2)
  println(view.to_ntriples())
}
