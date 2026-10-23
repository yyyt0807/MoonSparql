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
  }
}

///|
fn Parser::triples(self : Parser) -> Array[Pattern] raise QueryError {
  let s = self.slot()
  match s {
    Fixed(t) =>
      if self.template_mode && t.kind == LiteralKind {
        raise Syntax(self.position(), "literal template subject")
      }
    _ => ()
  }
  let result = []
  while true {
    let p = self.read_path()
    result.push(Triple(s, p, self.slot()))
    while self.sym(",") {
      result.push(Triple(s, p, self.slot()))
    }
    if !self.sym(";") {
      break
    }
    while self.sym(";") {
      ()
    }
    if self.current() == Symbol("}") || self.current() == Symbol(".") {
      break
    }
  }
  result
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
      let permitted = match self.current() {
        Symbol("}" | "{") => true
        Word(w) =>
          ["OPTIONAL", "FILTER", "BIND", "VALUES", "GRAPH", "MINUS"].contains(
            w.to_upper(),
          )
        _ => false
      }
      if !permitted {
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
    EndToken => true
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
) -> PreparedQuery raise QueryError {
  let p = Parser::new(source, limits)
  p.prefixes()
  let form = if p.word("SELECT") {
    Select
  } else if p.word("ASK") {
    Ask
  } else if p.word("CONSTRUCT") {
    Construct
  } else {
    raise Unsupported(p.position(), "expected SELECT, ASK or CONSTRUCT")
  }
  let distinct = form == Select && p.word("DISTINCT")
  let all = form == Select && p.sym("*")
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
  if form == Construct {
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
  ignore(p.word("WHERE"))
  let group = p.group()
  let group_by = []
  let having = []
  let order = []
  let mut offset = 0
  let mut limit : Int32? = None
  let mut saw_offset = false
  if p.word("GROUP") {
    p.require_word("BY")
    while !p.modifier() {
      group_by.push(p.expression())
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
  while p.current() != EndToken {
    if p.word("LIMIT") && limit is None {
      limit = Some(p.nonnegative())
    } else if p.word("OFFSET") && !saw_offset {
      offset = p.nonnegative()
      saw_offset = true
    } else {
      raise Unsupported(p.position(), "query modifier or trailing input")
    }
  }
  let query = Query::{
    form,
    projections,
    all,
    distinct,
    group,
    group_by,
    having,
    order,
    offset,
    limit,
    template,
  }
  validate_depth(query, limits.max_depth)
  validate_query(query)
  { query, limits, }
}
