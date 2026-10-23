///|
fn Expr::references(self : Expr, names : Map[String, Bool], inside_aggregate? : Bool = false)
  -> Unit raise QueryError {
  match self {
    Reference(name) => if !inside_aggregate { names[name] = true }
    Unary(_, e) => e.references(names, inside_aggregate~)
    Binary(_, a, b) => {
      a.references(names, inside_aggregate~)
      b.references(names, inside_aggregate~)
    }
    Call(_, args) => for arg in args { arg.references(names, inside_aggregate~) }
    Aggregate(_, value, _) => {
      if inside_aggregate { raise Syntax(0, "nested aggregate") }
      if value is Some(e) { e.references(names, inside_aggregate=true) }
    }
    _ => ()
  }
}

///|
fn validate_group(g : Group) -> Unit raise QueryError {
  let scope : Map[String, Bool] = {}
  for pat in g.patterns {
    match pat {
      Bind(e, name) => {
        if scope.get(name) is Some(_) { raise Syntax(0, "BIND variable already in scope") }
        if e.has_aggregate() { raise Syntax(0, "aggregate in BIND") }
      }
      Filter(e) => if e.has_aggregate() { raise Syntax(0, "aggregate in FILTER") }
      Nested(inner) | Optional(inner) | Minus(inner) | Graph(_, inner) => validate_group(inner)
      Union(groups) => for group in groups { validate_group(group) }
      _ => ()
    }
    Group::{ patterns: [pat] }.variables(scope)
  }
}

///|
fn validate_query(q : Query) -> Unit raise QueryError {
  validate_group(q.group)
  let scope = {}
  q.group.variables(scope)
  let grouped = query_grouped(q)
  if q.having.length() > 0 && !grouped { raise Syntax(0, "HAVING requires grouping") }
  let allowed : Map[String, Bool] = {}
  for expression in q.group_by {
    if expression.has_aggregate() { raise Syntax(0, "aggregate in GROUP BY") }
    if expression is Reference(name) { allowed[name] = true }
  }
  if grouped && q.all { raise Syntax(0, "SELECT * with grouping is outside profile") }
  for projection in q.projections {
    let plain = projection.expression is Reference(name) && name == projection.variable
    if !plain && scope.get(projection.variable) is Some(_) {
      raise Syntax(0, "projection alias already in scope")
    }
    let references = {}
    projection.expression.references(references)
    if grouped {
      for name, _ in references {
        if allowed.get(name) is None { raise Syntax(0, "ungrouped projected variable " + name) }
      }
    }
    allowed[projection.variable] = true
    scope[projection.variable] = true
  }
}
