///|
async fn read_input(file : String, limits : @q.Limits) -> String {
  if @fs.file_size(file[:]) > limits.max_query_chars.to_int64() {
    raise Failure("input file exceeds CLI byte budget")
  }
  @fs.read_file(file[:]).text()
}

///|
fn manifest_string(fields : Map[String, Json], key : String) -> String? raise {
  match fields.get(key) {
    None => None
    Some(Json::String(value)) => Some(value)
    _ => raise Failure("dataset field must be a string: " + key)
  }
}

///|
fn manifest_documents(
  fields : Map[String, Json],
  key : String,
) -> Array[(@q.Term, String)] raise {
  match fields.get(key) {
    None => []
    Some(Json::Object(documents)) => {
      let output = []
      for name, entry in documents {
        match entry {
          Json::String(source) => output.push((@q.iri(name), source))
          _ => raise Failure("dataset document must be Turtle text")
        }
      }
      output
    }
    _ => raise Failure("dataset field must be an IRI to Turtle object: " + key)
  }
}

///|
fn manifest_query(
  source : String,
  query : String,
  limits : @q.Limits,
) -> (@q.PreparedQuery, @q.Dataset) raise {
  guard @json.parse(source[:], reject_duplicate_keys=true, max_nesting_depth=8)
    is Json::Object(fields) else {
    raise Failure("dataset manifest must be a JSON object")
  }
  for key in fields.keys() {
    if !["base", "default", "named", "sources"].contains(key) {
      raise Failure("unknown dataset field: " + key)
    }
  }
  let base_uri = manifest_string(fields, "base")
  let default_graph = manifest_string(fields, "default").unwrap_or("")
  let named = manifest_documents(fields, "named")
  let catalog = manifest_documents(fields, "sources")
  let query = @q.prepare(query, limits~, base_uri?)
  let documents = if query.dataset_sources().is_empty() {
    named
  } else {
    named + catalog
  }
  (query, @q.Dataset::from_documents(default_graph, documents, limits~))
}

///|
async fn main {
  let args = @env.args()
  let limits = @q.Limits::default()
  if args.length() == 2 && args[1] == "version" {
    println("moonsparql 0.2.0")
    return
  }
  if args.length() == 3 && args[1] == "--inspect" {
    println(
      @q.prepare(read_input(args[2], limits), limits~).profile().to_json(),
    )
    return
  }
  let manifest = args.length() == 5 && args[1] == "--dataset"
  let shift = if manifest { 1 } else { 0 }
  if args.length() != 4 + shift ||
    !["json", "tsv", "rdf"].contains(args[3 + shift]) {
    raise Failure(
      "usage: moonsparql [--dataset] DATA QUERY.rq json|tsv|rdf or --inspect QUERY.rq",
    )
  }
  let data_text = read_input(args[1 + shift], limits)
  let query_text = read_input(args[2 + shift], limits)
  let format = args[3 + shift]
  let (query, data) = if manifest {
    manifest_query(data_text, query_text, limits)
  } else {
    (
      @q.prepare(query_text, limits~),
      @q.Dataset::from_turtle(data_text, limits~),
    )
  }
  if (query.form() == "CONSTRUCT") != (format == "rdf") {
    raise Failure(
      "CONSTRUCT requires rdf output; SELECT/ASK require json or tsv",
    )
  }
  let result = query.execute(data)
  println(
    match format {
      "rdf" => result.to_ntriples()
      "tsv" => result.to_tsv()
      _ => result.to_json()
    },
  )
}
