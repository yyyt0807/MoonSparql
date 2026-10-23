///|
fn validate_expression_depth(
  root : Expr,
  maximum : Int32,
) -> Unit raise QueryError {
  let stack = [(root, 1)]
  while stack.pop() is Some((expression, depth)) {
    if depth > maximum {
      raise Resource("expression tree depth")
    }
    match expression {
      Unary(_, e) => stack.push((e, depth + 1))
      Binary(_, a, b) => {
        stack.push((a, depth + 1))
        stack.push((b, depth + 1))
      }
      Call(_, args) =>
        for e in args {
          stack.push((e, depth + 1))
        }
      Aggregate(_, e, _) => if e is Some(e) { stack.push((e, depth + 1)) }
      _ => ()
    }
  }
}

///|
fn validate_path_depth(root : Path, maximum : Int32) -> Unit raise QueryError {
  let stack = [(root, 1)]
  while stack.pop() is Some((path, depth)) {
    if depth > maximum {
      raise Resource("property path tree depth")
    }
    match path {
      Inverse(p) | ZeroMore(p) | OneMore(p) | ZeroOne(p) =>
        stack.push((p, depth + 1))
      Sequence(a, b) | Alternative(a, b) => {
        stack.push((a, depth + 1))
        stack.push((b, depth + 1))
      }
      _ => ()
    }
  }
}

///|
fn validate_group_depth(
  group : Group,
  maximum : Int32,
) -> Unit raise QueryError {
  for pattern in group.patterns {
    match pattern {
      Triple(_, path, _) => validate_path_depth(path, maximum)
      Filter(e) | Bind(e, _) => validate_expression_depth(e, maximum)
      Nested(g) | Optional(g) | Graph(_, g) | Minus(g) =>
        validate_group_depth(g, maximum)
      Union(groups) =>
        for g in groups {
          validate_group_depth(g, maximum)
        }
      _ => ()
    }
  }
}

///|
fn validate_depth(q : Query, maximum : Int32) -> Unit raise QueryError {
  validate_group_depth(q.group, maximum)
  for p in q.projections {
    validate_expression_depth(p.expression, maximum)
  }
  for e in q.group_by {
    validate_expression_depth(e, maximum)
  }
  for e in q.having {
    validate_expression_depth(e, maximum)
  }
  for (e, _) in q.order {
    validate_expression_depth(e, maximum)
  }
}
