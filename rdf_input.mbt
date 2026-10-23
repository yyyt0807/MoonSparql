///|
fn decode_view(bytes : ArrayView[Byte]) -> String raise QueryError {
  try @utf8.decode(Bytes::from_array(bytes.to_array())) catch {
    _ => raise InvalidInput("RDF input is not valid UTF-8")
  }
}

///|
fn materialized_term(kind : @nq.TermKind, bytes : ArrayView[Byte], limits : Limits)
  -> Term raise QueryError {
  let text = decode_view(bytes)
  if kind == @nq.BNode {
    if !text.has_prefix("_:") { raise InvalidInput("blank-node lexical representation") }
    return blank(text[2:].to_string())
  }
  let parser = Parser::new(text, limits)
  let result = parser.read_term()
  if parser.current() != EndToken { raise InvalidInput("trailing RDF term input") }
  result
}

///|
pub fn Dataset::from_turtle(source : String, limits? : Limits = Limits::default())
  -> Dataset raise QueryError {
  limits.validate()
  if source.length() > limits.max_query_chars { raise Resource("RDF input characters") }
  // This integration profile accepts explicit RDF terms. Anonymous property
  // lists and collections need source-aware blank allocation and are rejected.
  let lexical = lex(source, limits)
  for token in lexical {
    if token.value == Symbol("[") || token.value == Symbol("]") ||
      token.value == Symbol("(") || token.value == Symbol(")") {
      raise Unsupported(token.position, "anonymous Turtle nodes and collections")
    }
  }
  let bytes = @utf8.encode(source).to_array()
  let engine = @trig.TrigEngine::from_bytes(bytes, dialect=@trig.Turtle)
  let parser = @trig.TrigSliceParser::new(engine, bytes[:], lenient=true)
  let (spans, errors) = parser.parse_all()
  if errors.length() > 0 { raise InvalidInput("MoonTTL rejected Turtle syntax") }
  if spans.length() > limits.max_triples { raise Resource("RDF input quads") }
  let materializer = @trig.TrigMaterializer::new(bytes[:], parser.prefixes(),
    bases=parser.bases(), rdf12=false)
  let (quads, errors) = materializer.materialize_all(spans, deep_validate=true)
  if errors.length() > 0 { raise InvalidInput("MoonTTL rejected RDF terms") }
  let output = []
  for q in quads {
    if q.g_kind != @nq.DefaultGraph { raise Unsupported(0, "named graphs in Turtle input") }
    output.push(quad(materialized_term(q.s_kind, q.s_view, limits),
      materialized_term(@nq.Iri, q.predicate, limits),
      materialized_term(q.o_kind, q.o_view, limits)))
  }
  Dataset::from_quads(output, limits~)
}
