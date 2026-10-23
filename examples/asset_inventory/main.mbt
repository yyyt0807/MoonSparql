///|
// Asset ownership and transitive dependencies
fn main raise {
  let data = @q.Dataset::from_turtle(
    "@prefix e: <urn:asset:> .\n" +
    "e:portal e:depends e:api .\ne:api e:depends e:database .\n" +
    "e:portal e:owner \"web-team\" .\ne:api e:owner \"platform\" .\n" +
    "e:database e:owner \"data-team\" .\n",
  )
  let result = @q.prepare(
    "PREFIX e: <urn:asset:> SELECT ?asset ?owner {" +
    "?asset e:depends+ e:database OPTIONAL {?asset e:owner ?owner}} ORDER BY ?asset",
  ).execute(data)
  assert_eq(result.rows().length(), 2)
  assert_eq(result.rows()[0].get("owner").unwrap().lexical(), "platform")
  println(result.to_tsv())
}
