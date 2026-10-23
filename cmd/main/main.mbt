///|
async fn main {
  let args = @env.args()
  if args.length() == 2 && args[1] == "version" {
    println("moonsparql 0.1.0")
    return
  }
  if args.length() != 4 || !["json", "tsv", "rdf"].contains(args[3]) {
    raise Failure("usage: moonsparql DATA.ttl QUERY.rq json|tsv|rdf")
  }
  let limits = @q.Limits::default()
  // Check file size before materializing input. The library separately checks
  // decoded character counts and Turtle tokens.
  for file in [args[1], args[2]] {
    if @fs.file_size(file[:]) > limits.max_query_chars.to_int64() {
      raise Failure("input file exceeds CLI byte budget")
    }
  }
  let data_text = @fs.read_file(args[1][:]).text()
  let query_text = @fs.read_file(args[2][:]).text()
  let query = @q.prepare(query_text, limits~)
  if (query.form() == "CONSTRUCT") != (args[3] == "rdf") {
    raise Failure(
      "CONSTRUCT requires rdf output; SELECT/ASK require json or tsv",
    )
  }
  let data = @q.Dataset::from_turtle(data_text, limits~)
  let result = query.execute(data)
  println(
    match args[3] {
      "rdf" => result.to_ntriples()
      "tsv" => result.to_tsv()
      _ => result.to_json()
    },
  )
}
