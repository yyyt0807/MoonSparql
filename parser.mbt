///|
pub struct PreparedQuery {
  priv query : Query
  priv limits : Limits
}

///|
pub fn PreparedQuery::form(self : PreparedQuery) -> String {
  match self.query.form {
    Select => "SELECT"
    Ask => "ASK"
    Construct => "CONSTRUCT"
    Describe => "DESCRIBE"
  }
}

///|
fn Parser::triples(self : Parser) -> Array[Pattern] raise QueryError {
  let result = []
  let s = self.graph_node(result)
  match s {
    Fixed(t) =>
      if self.template_mode && t.kind == LiteralKind {
        raise Syntax(self.position(), "literal template subject")
      }
    _ => ()
  }
  if result.is_empty() || !self.end_of_triples() {
    self.predicate_list(s, result)
  }
  result
}

///|
fn Parser::end_of_triples(self : Parser) -> Bool {
  match self.current() {
    Symbol("}" | "." | "]" | "{") | EndToken => true
    Word(word) =>
      ["OPTIONAL", "FILTER", "BIND", "VALUES", "GRAPH", "MINUS"].contains(
        word.to_upper(),
      )
    _ => false
  }
}

///|
fn Parser::predicate_list(
  self : Parser,
  s : Slot,
  result : Array[Pattern],
) -> Unit raise QueryError {
  while true {
    let p = self.read_path()
    let object = self.graph_node(result)
    result.push(Triple(s, p, object))
    while self.sym(",") {
      let object = self.graph_node(result)
      result.push(Triple(s, p, object))
    }
    if !self.sym(";") {
      break
    }
    while self.sym(";") {
      ()
    }
    if self.end_of_triples() {
      break
    }
  }
}

///|
fn Parser::anonymous_node(self : Parser) -> Slot raise QueryError {
  let id = self.anonymous_nodes.to_string()
  self.anonymous_nodes += 1
  if self.template_mode {
    Fixed(blank("!anonymous" + id))
  } else {
    // This prefix cannot be written as a SPARQL variable by the lexer.
    Variable("\u0000" + id)
  }
}

///|
fn Parser::graph_node(
  self : Parser,
  output : Array[Pattern],
) -> Slot raise QueryError {
  if self.sym("[") {
    self.enter()
    let node = self.anonymous_node()
    if !self.sym("]") {
      self.predicate_list(node, output)
      self.expect("]")
    }
    self.depth -= 1
    return node
  }
  if !self.sym("(") {
    return self.slot()
  }
  self.enter()
  let members = []
  while !self.sym(")") {
    members.push(self.graph_node(output))
  }
  let mut rest = Slot::Fixed(iri(rdf_namespace() + "nil"))
  let first = Path::Predicate(iri(rdf_namespace() + "first"))
  let next = Path::Predicate(iri(rdf_namespace() + "rest"))
  for i = members.length() - 1; i >= 0; i = i - 1 {
    let node = self.anonymous_node()
    output.push(Triple(node, first, members[i]))
    output.push(Triple(node, next, rest))
    rest = node
  }
  self.depth -= 1
  rest
}

///|
fn Parser::values(self : Parser) -> Pattern raise QueryError {
  let list = self.sym("(")
  let names = []
  if list {
    while !self.sym(")") {
      names.push(self.variable())
    }
  } else {
    names.push(self.variable())
  }
  let seen : Map[String, Bool] = Map([])
  for name in names {
    if seen.get(name) is Some(_) {
      raise Syntax(self.position(), "duplicate VALUES variable")
    }
    seen[name] = true
  }
  self.expect("{")
  let rows = []
  while !self.sym("}") {
    if list {
      self.expect("(")
    }
    let values = []
    for _ in names {
      values.push(
        if self.word("UNDEF") {
          None
        } else {
          Some(self.read_term())
        },
      )
    }
    if list {
      self.expect(")")
    }
    rows.push(values)
    if rows.length() > self.limits.max_bindings {
      raise Resource("VALUES rows")
    }
  }
  Values(names, rows)
}

///|
fn Parser::group(self : Parser) -> Group raise QueryError {
  self.enter()
  self.expect("{")
  if self.word("SELECT") {
    if self.template_mode {
      raise Syntax(self.position(), "subquery in template")
    }
    let query = self.query(Select, nested=true)
    self.expect("}")
    self.depth -= 1
    return { patterns: [Subselect(query)], }
  }
  let patterns = []
  while !self.sym("}") {
    let pat = if self.word("OPTIONAL") {
      Optional(self.group())
    } else if self.word("MINUS") {
      Minus(self.group())
    } else if self.word("FILTER") {
      Filter(self.expression())
    } else if self.word("BIND") {
      self.expect("(")
      let expression = self.expression()
      self.require_word("AS")
      let name = self.variable()
      self.expect(")")
      Bind(expression, name)
    } else if self.word("VALUES") {
      self.values()
    } else if self.word("GRAPH") {
      let graph = self.slot()
      if graph is Fixed(term) && term.kind != IriKind {
        raise Syntax(self.position(), "GRAPH requires an IRI or variable")
      }
      Graph(graph, self.group())
    } else if self.current() == Symbol("{") {
      let inner = self.group()
      let alternatives = [inner]
      while self.word("UNION") {
        alternatives.push(self.group())
      }
      if alternatives.length() == 1 {
        Nested(inner)
      } else {
        Union(alternatives)
      }
    } else {
      if self.current() == EndToken {
        raise Syntax(self.position(), "unclosed group")
      }
      match self.current() {
        Word(w) if ["SERVICE", "SELECT", "DESCRIBE"].contains(w.to_upper()) =>
          raise Unsupported(self.position(), w)
        _ => ()
      }
      let triples = self.triples()
      patterns.append(triples)
      if self.sym(".") {
        continue
      }
      if !self.end_of_triples() {
        raise Syntax(self.position(), "expected triple separator")
      }
      continue
    }
    patterns.push(pat)
    ignore(self.sym("."))
  }
  self.depth -= 1
  { patterns, }
}

///|
fn Parser::nonnegative(self : Parser) -> Int32 raise QueryError {
  let text = match self.advance() {
    NumToken(n) => n
    _ => raise Syntax(self.position(), "expected nonnegative integer")
  }
  let mut value = 0
  for c in text.to_array() {
    if !digit(c) {
      raise Syntax(self.position(), "expected nonnegative integer")
    }
    let n = c.to_int() - 48
    if value > (2147483647 - n) / 10 {
      raise Syntax(self.position(), "integer too large")
    }
    value = value * 10 + n
  }
  value
}

///|
fn Parser::modifier(self : Parser) -> Bool {
  match self.current() {
    EndToken | Symbol("}") => true
    Word(w) =>
      ["GROUP", "HAVING", "ORDER", "LIMIT", "OFFSET", "VALUES"].contains(
        w.to_upper(),
      )
    _ => false
  }
}

///|
pub fn prepare(
  source : String,
  limits~ : Limits = Limits::default(),
  base_uri? : String,
) -> PreparedQuery raise QueryError {
  let p = Parser::new(source, limits, base_uri?)
  p.prefixes()
  let form = if p.word("SELECT") {
    Select
  } else if p.word("ASK") {
    Ask
  } else if p.word("CONSTRUCT") {
    Construct
  } else if p.word("DESCRIBE") {
    Describe
  } else {
    raise Unsupported(
      p.position(),
      "expected SELECT, ASK, CONSTRUCT or DESCRIBE",
    )
  }
  let query = p.query(form)
  if p.current() != EndToken {
    raise Syntax(p.position(), "trailing query input")
  }
  validate_depth(query, limits.max_depth)
  validate_query(query)
  { query, limits, }
}

///|
fn Parser::query(
  p : Parser,
  form : QueryForm,
  nested~ : Bool = false,
) -> Query raise QueryError {
  let distinct = form == Select && p.word("DISTINCT")
  let reduced = form == Select && !distinct && p.word("REDUCED")
  let all = (form == Select || form == Describe) && p.sym("*")
  let describe = []
  if form == Describe && !all {
    while true {
      match p.current() {
        Var(_) => describe.push(Variable(p.variable()))
        IriToken(_) | Word(_) if p.current() is IriToken(_) ||
          (p.current() is Word(w) && w.contains(":")) => {
          let term = p.read_term()
          if term.kind != IriKind {
            raise Syntax(p.position(), "DESCRIBE requires a variable or IRI")
          }
          describe.push(Fixed(term))
        }
        _ => break
      }
    }
    if describe.is_empty() {
      raise Syntax(p.position(), "DESCRIBE requires a variable, IRI or *")
    }
  }
  let projections = []
  let names : Map[String, Bool] = Map([])
  if form == Select && !all {
    while p.current() is Var(_) || p.current() == Symbol("(") {
      let item = if p.sym("(") {
        let expression = p.expression()
        p.require_word("AS")
        let variable = p.variable()
        p.expect(")")
        Projection::{ expression, variable, }
      } else {
        let variable = p.variable()
        Projection::{ expression: Reference(variable), variable, }
      }
      if names.get(item.variable) is Some(_) {
        raise Syntax(p.position(), "duplicate projected variable")
      }
      names[item.variable] = true
      projections.push(item)
    }
    if projections.length() == 0 {
      raise Syntax(p.position(), "empty projection")
    }
  }
  let template = []
  let shorthand = form == Construct && p.current() != Symbol("{")
  if form == Construct && !shorthand {
    p.set_template_mode(true)
    let t = p.group()
    p.set_template_mode(false)
    for pat in t.patterns {
      match pat {
        Triple(s, path, o) =>
          match path {
            Predicate(_) | PathVar(_) => template.push((s, path, o))
            _ => raise Syntax(p.position(), "paths cannot appear in a template")
          }
        _ => raise Syntax(p.position(), "template only accepts triples")
      }
    }
  }
  let datasets = []
  while p.word("FROM") {
    if nested {
      raise Syntax(p.position(), "dataset clause in subquery")
    }
    let named = p.word("NAMED")
    let source = p.read_term()
    if source.kind != IriKind {
      raise Syntax(p.position(), "dataset source must be an IRI")
    }
    datasets.push((source, named))
  }
  let has_where = p.word("WHERE")
  if shorthand && !has_where {
    raise Syntax(p.position(), "expected WHERE")
  }
  let group = if form == Describe && !has_where && p.current() != Symbol("{") {
    Group::{ patterns: [], }
  } else {
    p.group()
  }
  if shorthand {
    for pattern in group.patterns {
      match pattern {
        Triple(s, Predicate(_) | PathVar(_) as path, o) =>
          template.push((s, path, o))
        _ =>
          raise Syntax(
            p.position(),
            "CONSTRUCT WHERE requires ordinary triples",
          )
      }
    }
  }
  let group_by = []
  let having = []
  let order = []
  let mut offset = 0
  let mut limit : Int32? = None
  let mut saw_offset = false
  if p.word("GROUP") {
    p.require_word("BY")
    while !p.modifier() {
      if p.sym("(") {
        let e = p.expression()
        let group_name = if p.word("AS") { Some(p.variable()) } else { None }
        p.expect(")")
        group_by.push((e, group_name))
      } else {
        group_by.push((p.expression(), None))
      }
    }
    if group_by.length() == 0 {
      raise Syntax(p.position(), "empty GROUP BY")
    }
  }
  if p.word("HAVING") {
    while !p.modifier() {
      having.push(p.expression())
    }
    if having.length() == 0 {
      raise Syntax(p.position(), "empty HAVING")
    }
  }
  if p.word("ORDER") {
    p.require_word("BY")
    while !p.modifier() {
      let descending = p.word("DESC")
      if descending || p.word("ASC") {
        p.expect("(")
        let expression = p.expression()
        p.expect(")")
        order.push((expression, descending))
      } else {
        order.push((p.expression(), false))
      }
    }
    if order.length() == 0 {
      raise Syntax(p.position(), "empty ORDER BY")
    }
  }
  while p.current() != EndToken && p.current() != Symbol("}") {
    if p.word("LIMIT") && limit is None {
      limit = Some(p.nonnegative())
    } else if p.word("OFFSET") && !saw_offset {
      offset = p.nonnegative()
      saw_offset = true
    } else if p.current() is Word(w) && w.to_upper() == "VALUES" {
      break
    } else {
      raise Unsupported(p.position(), "query modifier or trailing input")
    }
  }
  let trailing = Group::{
    patterns: if p.word("VALUES") {
      [p.values()]
    } else {
      []
    },
  }
  Query::{
    form,
    projections,
    all,
    distinct,
    reduced,
    describe,
    base_uri: p.base_uri,
    group,
    group_by,
    datasets,
    trailing,
    having,
    order,
    offset,
    limit,
    template,
  }
}
