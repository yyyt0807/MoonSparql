///|
fn main raise {
  let data = @q.Dataset::from_turtle(
    "<urn:item> <urn:label> 'abc' ; <urn:category> 'open', 'research' .",
  )
  let index = @q.prepare(
    "SELECT REDUCED ?item (SHA256(?label) AS ?fingerprint) { " +
    "?item <urn:label> ?label ; <urn:category> ?category } ORDER BY ?item",
  ).execute(data)
  assert_eq(index.rows().length(), 1)
  assert_eq(
    index.rows()[0].get("fingerprint"),
    Some(
      @q.literal(
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      ),
    ),
  )
  println(index.to_tsv())
  let description = @q.prepare(
    "DESCRIBE ?item { ?item <urn:category> 'research' }",
  ).execute(data)
  assert_eq(description.graph().length(), 3)
  println(description.to_ntriples())
}
