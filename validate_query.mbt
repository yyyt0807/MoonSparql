///|
fn Expr::references(
  self : Expr,
  names : Map[String, Bool],
  inside_aggregate~ : Bool = false,
) -> Unit raise QueryError {
  match self {
    Reference(name) => if !inside_aggregate { names[name] = true }
    Unary(_, e) => e.references(names, inside_aggregate~)
    Binary(_, a, b) => {
      a.references(names, inside_aggregate~)
      b.references(names, inside_aggregate~)
    }
    Call(_, args) =>
      for arg in args {
        arg.references(names, inside_aggregate~)
      }
    Aggregate(_, value, _, _) => {
      if inside_aggregate {
        raise Syntax(0, "nested aggregate")
      }
      if value is Some(e) {
        e.references(names, inside_aggregate=true)
      }
    }
    Exists(g, _) => validate_group(g)
    _ => ()
  }
}

///|
fn validate_group(g : Group) -> Unit raise QueryError {
  let scope : Map[String, Bool] = Map([])
  for pat in g.patterns {
    match pat {
      Bind(e, name) => {
        if scope.get(name) is Some(_) {
          raise Syntax(0, "BIND variable already in scope")
        }
        if e.has_aggregate() {
          raise Syntax(0, "aggregate in BIND")
        }
        e.references(Map([]))
      }
      Filter(e) => {
        if e.has_aggregate() {
          raise Syntax(0, "aggregate in FILTER")
        }
        e.references(Map([]))
      }
      Subselect(q) => validate_query(q)
      Nested(inner) | Optional(inner) | Minus(inner) | Graph(_, inner) =>
        validate_group(inner)
      Union(groups) =>
        for group in groups {
          validate_group(group)
        }
      _ => ()
    }
    Group::{ patterns: [pat], }.variables(scope)
  }
}

///|
fn validate_query(q : Query) -> Unit raise QueryError {
  validate_group(q.group)
  let scope = Map([])
  q.group.variables(scope)
  let grouped = query_grouped(q)
  if q.having.length() > 0 && !grouped {
    raise Syntax(0, "HAVING requires grouping")
  }
  let allowed : Map[String, Bool] = Map([])
  for (expression, group_name) in q.group_by {
    if expression.has_aggregate() {
      raise Syntax(0, "aggregate in GROUP BY")
    }
    expression.references(Map([]))
    if group_name is Some(name) {
      if scope.contains(name) || allowed.contains(name) {
        raise Syntax(0, "GROUP BY alias already in scope")
      }
      allowed[name] = true
      scope[name] = true
    } else if expression is Reference(name) {
      allowed[name] = true
    }
  }
  if grouped && q.all {
    raise Syntax(0, "SELECT * with grouping is outside profile")
  }
  for expression in q.having {
    check_group_references(expression, allowed)
  }
  q.trailing.variables(scope)
  q.trailing.variables(allowed)
  for projection in q.projections {
    let plain = projection.expression is Reference(name) &&
      name == projection.variable
    if !plain && scope.get(projection.variable) is Some(_) {
      raise Syntax(0, "projection aliased already in scope")
    }
    if grouped {
      check_group_references(projection.expression, allowed)
    } else {
      projection.expression.references(Map([]))
    }
    allowed[projection.variable] = true
    scope[projection.variable] = true
  }
  for (expression, _) in q.order {
    if grouped {
      check_group_references(expression, allowed)
    } else {
      expression.references(Map([]))
    }
  }
}

///|
fn check_group_references(
  e : Expr,
  allowed : Map[String, Bool],
) -> Unit raise QueryError {
  let references = Map([])
  e.references(references)
  for name, _ in references {
    if !allowed.contains(name) {
      raise Syntax(0, "ungrouped variable " + name)
    }
  }
}
