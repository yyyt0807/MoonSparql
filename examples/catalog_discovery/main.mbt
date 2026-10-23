///|
// Cross-catalog metadata discovery
fn main raise {
  let data = @q.Dataset::from_turtle(
    "@prefix e: <urn:catalog:> .\n" +
    "e:weather e:topic \"climate\" .\ne:weather e:publisher \"Institute A\" .\n" +
    "e:traffic e:topic \"transport\" .\ne:traffic e:publisher \"City B\" .\n" +
    "e:air e:topic \"climate\" .\ne:air e:publisher \"City B\" .\n",
  )
  let result = @q.prepare(
    "PREFIX e: <urn:catalog:> SELECT ?dataset ?publisher {" +
    "VALUES ?topic {\"climate\"} ?dataset e:topic ?topic; e:publisher ?publisher} " +
    "ORDER BY ?publisher",
  ).execute(data)
  assert_eq(result.rows().length(), 2)
  assert_eq(result.rows()[0].get("publisher").unwrap().lexical(), "City B")
  println(result.to_json())
}
