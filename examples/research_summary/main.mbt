///|
// Research aggregation and derived data
fn main raise {
  let data = @q.Dataset::from_turtle(
    "@prefix e: <urn:study:> .\n" +
    "e:o1 e:site \"north\" .\ne:o1 e:value 10 .\n" +
    "e:o2 e:site \"north\" .\ne:o2 e:value 20 .\n" +
    "e:o3 e:site \"south\" .\ne:o3 e:value 9 .\n",
  )
  let result = @q.prepare(
    "PREFIX e: <urn:study:> SELECT ?site (COUNT(*) AS ?count) " +
    "(AVG(?value) AS ?mean) {?obs e:site ?site; e:value ?value} " +
    "GROUP BY ?site HAVING(COUNT(*)>=2)",
  ).execute(data)
  assert_eq(result.rows().length(), 1)
  assert_eq(result.rows()[0].get("mean").unwrap().lexical(), "15.0")
  let view = @q.prepare(
    "PREFIX e: <urn:study:> CONSTRUCT {?obs e:review \"high\"} " +
    "WHERE {?obs e:value ?v FILTER(?v>=15)}",
  ).execute(data)
  assert_eq(view.graph().length(), 1)
  println(result.to_tsv())
  println(view.to_ntriples())
}
