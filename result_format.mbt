///|
fn Term::binding_json(self : Term) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["type"] = Json::string(
    match self.kind {
      IriKind => "uri"
      BlankKind => "bnode"
      LiteralKind => "literal"
    },
  )
  fields["value"] = Json::string(self.lexical)
  if self.kind == LiteralKind {
    match self.language {
      Some(lang) => fields["xml:lang"] = Json::string(lang)
      None => fields["datatype"] = Json::string(self.datatype)
    }
  }
  Json::object(fields)
}

///|
pub fn validate_result_json(source : String) -> Bool {
  try {
    let value = @json.parse(source[:], reject_duplicate_keys=true)
    value is Json::Object(_)
  } catch {
    _ => false
  }
}

///|
pub fn QueryResult::to_json(self : QueryResult) -> String {
  match self.answer {
    Some(answer) =>
      Json::object({
        "head": Json::object({}),
        "boolean": Json::boolean(answer),
      }).stringify()
    None => {
      let rows = self.bindings.map(row => {
        let fields : Map[String, Json] = Map([])
        for name in self.variables {
          if row.get(name) is Some(t) {
            fields[name] = t.binding_json()
          }
        }
        Json::object(fields)
      })
      Json::object({
        "head": Json::object({
          "vars": Json::array(self.variables.map(Json::string)),
        }),
        "results": Json::object({ "bindings": Json::array(rows) }),
      }).stringify()
    }
  }
}

///|
pub fn QueryResult::to_ntriples(self : QueryResult) -> String {
  let text = StringBuilder()
  for q in self.constructed {
    text.write_string(
      q.subject.ntriples() +
      " " +
      q.predicate.ntriples() +
      " " +
      q.object.ntriples() +
      " .\n",
    )
  }
  text.to_string()
}

///|
fn tsv_cell(t : Term?) -> String {
  match t {
    None => ""
    Some(t) => t.ntriples()
  }
}

///|
pub fn QueryResult::to_tsv(self : QueryResult) -> String {
  if self.answer is Some(answer) {
    return if answer { "true\n" } else { "false\n" }
  }
  let text = StringBuilder()
  text.write_string(self.variables.map(v => "?" + v).join("\t"))
  text.write_string("\n")
  for row in self.bindings {
    text.write_string(self.variables.map(v => tsv_cell(row.get(v))).join("\t"))
    text.write_string("\n")
  }
  text.to_string()
}
