///|
#derive(Eq, @debug.Debug)
pub(all) enum TermKind {
  IriKind
  BlankKind
  LiteralKind
}

///|
#derive(Eq, @debug.Debug)
pub struct Term {
  priv kind : TermKind
  priv lexical : String
  priv datatype : String
  priv language : String?
}

///|
pub fn xsd_namespace() -> String {
  "http://www.w3.org/2001/XMLSchema#"
}

///|
pub fn rdf_namespace() -> String {
  "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
}

///|
fn check_iri(value : String) -> Unit raise QueryError {
  if !(value.split_once(":") is Some((scheme, _)) &&
    valid_scheme(scheme.to_owned())) {
    raise InvalidTerm("an absolute IRI is required")
  }
  for c in value.to_array() {
    let n = c.to_int()
    if n <= 32 ||
      n == 127 ||
      c == '<' ||
      c == '>' ||
      c == '"' ||
      c == '{' ||
      c == '}' ||
      c == '|' ||
      c == '^' ||
      c == '`' ||
      c == '\\' {
      raise InvalidTerm("forbidden IRI character")
    }
  }
}

///|
pub fn iri(value : String) -> Term raise QueryError {
  check_iri(value)
  { kind: IriKind, lexical: value, datatype: "", language: None, }
}

///|
pub fn blank(value : String) -> Term raise QueryError {
  if value.length() == 0 {
    raise InvalidTerm("empty blank node identifier")
  }
  for c in value.to_array() {
    if c.to_int() <= 32 || c == '<' || c == '>' || c == '"' || c == '\\' {
      raise InvalidTerm("invalid blank node identifier")
    }
  }
  { kind: BlankKind, lexical: value, datatype: "", language: None, }
}

///|
pub fn literal(value : String) -> Term {
  {
    kind: LiteralKind,
    lexical: value,
    datatype: xsd_namespace() + "string",
    language: None,
  }
}

///|
pub fn typed_literal(
  value : String,
  datatype : String,
) -> Term raise QueryError {
  check_iri(datatype)
  if datatype == rdf_namespace() + "langString" {
    raise InvalidTerm("rdf:langString requires a language tag")
  }
  { kind: LiteralKind, lexical: value, datatype, language: None, }
}

///|
pub fn language_literal(
  value : String,
  language : String,
) -> Term raise QueryError {
  let parts = language.split("-").to_array()
  if parts.length() == 0 || language.length() == 0 {
    raise InvalidTerm("empty language tag")
  }
  for i, part in parts {
    if part.length() == 0 {
      raise InvalidTerm("empty language subtag")
    }
    for c in part.to_array() {
      let n = c.to_int()
      let alpha = (n >= 65 && n <= 90) || (n >= 97 && n <= 122)
      if !alpha && !(i > 0 && n >= 48 && n <= 57) {
        raise InvalidTerm("invalid language subtag")
      }
    }
  }
  {
    kind: LiteralKind,
    lexical: value,
    datatype: rdf_namespace() + "langString",
    language: Some(language.to_lower()),
  }
}

///|
pub fn Term::kind(self : Term) -> TermKind {
  self.kind
}

///|
pub fn Term::lexical(self : Term) -> String {
  self.lexical
}

///|
pub fn Term::datatype(self : Term) -> String? {
  if self.kind == LiteralKind {
    Some(self.datatype)
  } else {
    None
  }
}

///|
pub fn Term::language(self : Term) -> String? {
  self.language
}

///|
fn key_part(s : String) -> String {
  s.length().to_string() + ":" + s
}

///|
fn Term::key(self : Term) -> String {
  match self.kind {
    IriKind => "I" + key_part(self.lexical)
    BlankKind => "B" + key_part(self.lexical)
    LiteralKind =>
      "L" +
      key_part(self.lexical) +
      key_part(self.datatype) +
      key_part(self.language.unwrap_or(""))
  }
}

///|
fn json_quote(s : String) -> String {
  Json::string(s).stringify()
}

///|
pub fn Term::ntriples(self : Term) -> String {
  match self.kind {
    IriKind => "<" + self.lexical + ">"
    BlankKind => "_:" + self.lexical
    LiteralKind => {
      let text = json_quote(self.lexical)
      match self.language {
        Some(lang) => text + "@" + lang
        None =>
          if self.datatype == xsd_namespace() + "string" {
            text
          } else {
            text + "^^<" + self.datatype + ">"
          }
      }
    }
  }
}

///|
#derive(Eq, @debug.Debug)
pub struct Quad {
  priv subject : Term
  priv predicate : Term
  priv object : Term
  priv graph : Term?
}

///|
pub fn quad(
  subject : Term,
  predicate : Term,
  object : Term,
  graph? : Term,
) -> Quad raise QueryError {
  if subject.kind == LiteralKind || predicate.kind != IriKind {
    raise InvalidTerm("subject must be resource and predicate must be IRI")
  }
  match graph {
    Some(g) =>
      if g.kind != IriKind {
        raise InvalidTerm("graph name must be IRI")
      }
    None => ()
  }
  { subject, predicate, object, graph, }
}

///|
pub fn Quad::subject(self : Quad) -> Term {
  self.subject
}

///|
pub fn Quad::predicate(self : Quad) -> Term {
  self.predicate
}

///|
pub fn Quad::object(self : Quad) -> Term {
  self.object
}

///|
pub fn Quad::graph(self : Quad) -> Term? {
  self.graph
}

///|
fn Quad::key(self : Quad) -> String {
  let g = match self.graph {
    None => "D"
    Some(g) => g.key()
  }
  self.subject.key() + self.predicate.key() + self.object.key() + g
}

///|
pub extend TermKind with Eq::{equal, not_equal}

///|
pub extend TermKind with @debug.Debug::{to_repr}

///|
pub extend Term with Eq::{equal, not_equal}

///|
pub extend Term with @debug.Debug::{to_repr}

///|
pub extend Quad with Eq::{equal, not_equal}

///|
pub extend Quad with @debug.Debug::{to_repr}
