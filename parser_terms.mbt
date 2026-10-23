///|
priv struct Parser {
  tokens : Array[Token]
  mut i : Int32
  prefixes : Map[String, String]
  limits : Limits
  mut depth : Int32
  mut template_mode : Bool
}

///|
fn Parser::new(source : String, limits : Limits) -> Parser raise QueryError {
  {
    tokens: lex(source, limits),
    i: 0,
    prefixes: Map([]),
    limits,
    depth: 0,
    template_mode: false,
  }
}

///|
fn Parser::current(self : Parser) -> Lexeme {
  self.tokens[self.i].value
}

///|
fn Parser::set_template_mode(self : Parser, enabled : Bool) -> Unit {
  self.template_mode = enabled
}

///|
fn Parser::position(self : Parser) -> Int32 {
  self.tokens[self.i].position
}

///|
fn Parser::advance(self : Parser) -> Lexeme {
  let value = self.current()
  if value != EndToken {
    self.i += 1
  }
  value
}

///|
fn Parser::sym(self : Parser, symbol : String) -> Bool {
  if self.current() == Symbol(symbol) {
    self.i += 1
    true
  } else {
    false
  }
}

///|
fn Parser::word(self : Parser, wanted : String) -> Bool {
  match self.current() {
    Word(w) =>
      if w.to_upper() == wanted {
        self.i += 1
        true
      } else {
        false
      }
    _ => false
  }
}

///|
fn Parser::expect(self : Parser, symbol : String) -> Unit raise QueryError {
  if !self.sym(symbol) {
    raise Syntax(self.position(), "expected " + symbol)
  }
}

///|
fn Parser::require_word(self : Parser, word : String) -> Unit raise QueryError {
  if !self.word(word) {
    raise Syntax(self.position(), "expected " + word)
  }
}

///|
fn Parser::variable(self : Parser) -> String raise QueryError {
  match self.advance() {
    Var(name) => name
    _ => raise Syntax(self.position(), "expected variable")
  }
}

///|
fn Parser::enter(self : Parser) -> Unit raise QueryError {
  if self.depth >= self.limits.max_depth {
    raise Resource("query nesting")
  }
  self.depth += 1
}

///|
fn Parser::prefixes(self : Parser) -> Unit raise QueryError {
  while self.word("PREFIX") {
    let prefix = match self.advance() {
      Word(w) =>
        match w.split_once(":") {
          Some((prefix, tail)) =>
            if tail.length() == 0 {
              prefix.to_owned()
            } else {
              raise Syntax(self.position(), "prefix must end with colon")
            }
          None => raise Syntax(self.position(), "expected prefix name")
        }
      _ => raise Syntax(self.position(), "expected prefix name")
    }
    let base = match self.advance() {
      IriToken(v) => {
        check_iri(v)
        v
      }
      _ => raise Syntax(self.position(), "expected prefix IRI")
    }
    self.prefixes[prefix] = base
  }
  if self.word("BASE") {
    raise Unsupported(self.position(), "BASE and relative IRIs")
  }
}

///|
fn Parser::read_term(self : Parser) -> Term raise QueryError {
  let position = self.position()
  match self.advance() {
    IriToken(v) => iri(v)
    StringToken(v) =>
      if self.sym("@") {
        let lang = match self.advance() {
          Word(l) => l
          _ => raise Syntax(self.position(), "expected language tag")
        }
        language_literal(v, lang)
      } else if self.sym("^^") {
        let datatype = self.read_term()
        if datatype.kind != IriKind {
          raise Syntax(position, "datatype must be IRI")
        }
        typed_literal(v, datatype.lexical)
      } else {
        literal(v)
      }
    NumToken(n) => {
      if n.length() > self.limits.max_numeric_digits {
        raise Resource("numeric token digits")
      }
      let kind = if n.contains("e") || n.contains("E") {
        "double"
      } else if n.contains(".") {
        "decimal"
      } else {
        "integer"
      }
      typed_literal(n, xsd_namespace() + kind)
    }
    Symbol(sign) if sign == "+" || sign == "-" => {
      let value = self.read_term()
      if value.datatype != xsd_namespace() + "integer" &&
        value.datatype != xsd_namespace() + "decimal" &&
        value.datatype != xsd_namespace() + "double" {
        raise Syntax(position, "sign requires numeric literal")
      }
      typed_literal(sign + value.lexical, value.datatype)
    }
    Word(w) => {
      if w.to_lower() == "true" || w.to_lower() == "false" {
        return typed_literal(w.to_lower(), xsd_namespace() + "boolean")
      }
      match w.split_once(":") {
        Some((prefix, suffix)) =>
          if prefix == "_" {
            if !self.template_mode {
              raise Unsupported(
                position, "blank node query labels; use variables",
              )
            }
            blank(suffix.to_owned())
          } else {
            let base = match self.prefixes.get(prefix.to_owned()) {
              Some(v) => v
              None =>
                raise Syntax(position, "unknown prefix " + prefix.to_owned())
            }
            iri(base + suffix.to_owned())
          }
        None => raise Syntax(position, "expected RDF term")
      }
    }
    _ => raise Syntax(position, "expected RDF term")
  }
}

///|
fn Parser::slot(self : Parser) -> Slot raise QueryError {
  match self.current() {
    Var(_) => Variable(self.variable())
    _ => Fixed(self.read_term())
  }
}

///|
fn Parser::path_atom(self : Parser) -> Path raise QueryError {
  self.enter()
  let mut path = if self.sym("^") {
    Inverse(self.path_atom())
  } else if self.sym("(") {
    let inner = self.read_path()
    self.expect(")")
    inner
  } else if self.word("A") {
    Predicate(iri(rdf_namespace() + "type"))
  } else {
    match self.current() {
      Var(_) => PathVar(self.variable())
      _ => {
        let term = self.read_term()
        if term.kind != IriKind {
          raise Syntax(self.position(), "predicate must be IRI")
        }
        Predicate(term)
      }
    }
  }
  if self.sym("*") {
    path = ZeroMore(path)
  } else if self.sym("+") {
    path = OneMore(path)
  } else if self.sym("?") {
    path = ZeroOne(path)
  }
  self.depth -= 1
  path
}

///|
fn Parser::path_sequence(self : Parser) -> Path raise QueryError {
  let mut path = self.path_atom()
  while self.sym("/") {
    path = Sequence(path, self.path_atom())
  }
  path
}

///|
fn Parser::read_path(self : Parser) -> Path raise QueryError {
  let mut path = self.path_sequence()
  while self.sym("|") {
    path = Alternative(path, self.path_sequence())
  }
  path
}
