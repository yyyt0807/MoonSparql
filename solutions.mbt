///|
priv struct Solution {
  source : Binding
  projected : Binding
  keys : Array[Term?]
}

///|
fn term_rank(t : Term?) -> Int32 {
  match t {
    None => 0
    Some(t) =>
      match t.kind {
        BlankKind => 1
        IriKind => 2
        LiteralKind => 3
      }
  }
}

///|
fn order_terms(a : Term?, b : Term?, budget : Budget) -> Int32 raise QueryError {
  budget.tick()
  let ra = term_rank(a)
  let rb = term_rank(b)
  if ra != rb {
    return ra.compare(rb)
  }
  match (a, b) {
    (Some(x), Some(y)) => {
      if x.kind == IriKind || x.kind == BlankKind {
        return codepoint_compare(x.lexical, y.lexical)
      }
      let class_x = literal_order_class(x)
      let class_y = literal_order_class(y)
      if class_x != class_y {
        return class_x.compare(class_y)
      }
      let cmp = value_compare(x, y, budget.limits.max_numeric_digits) catch {
        Evaluation(_) => None
        e => raise e
      }
      match cmp {
        Some(v) => v
        None => x.key().compare(y.key())
      }
    }
    _ => 0
  }
}

///|
fn literal_order_class(t : Term) -> Int32 {
  if numeric_type(t) {
    let value = Some(numeric(t, 4096)) catch { _ => None }
    return match value {
      Some(Floating(v)) if v.is_nan() => 1
      Some(_) => 0
      None => 6
    }
  }
  if t.datatype == xsd_namespace() + "boolean" {
    2
  } else if t.datatype == xsd_namespace() + "string" {
    3
  } else if t.language is Some(_) {
    4
  } else {
    5
  }
}

///|
fn codepoint_compare(a : String, b : String) -> Int32 {
  let x = a.to_array()
  let y = b.to_array()
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  for i = 0; i < n; i = i + 1 {
    let cmp = x[i].to_int().compare(y[i].to_int())
    if cmp != 0 {
      return cmp
    }
  }
  x.length().compare(y.length())
}

///|
fn solution_compare(
  a : Solution,
  b : Solution,
  order : Array[(Expr, Bool)],
  budget : Budget,
) -> Int32 raise QueryError {
  for i, item in order {
    let cmp = order_terms(a.keys[i], b.keys[i], budget)
    if cmp != 0 {
      return if item.1 { -cmp } else { cmp }
    }
  }
  0
}

///|
fn sort_solutions(
  rows : Array[Solution],
  order : Array[(Expr, Bool)],
  budget : Budget,
) -> Array[Solution] raise QueryError {
  // Iterative stable mergesort avoids quadratic ORDER BY and recursive stack use.
  let mut current = rows.copy()
  let n = rows.length()
  let mut width = 1
  while width < n {
    let next = []
    let mut start = 0
    while start < n {
      let middle = if width > n - start { n } else { start + width }
      let end = if width > n - middle { n } else { middle + width }
      let mut a = start
      let mut b = middle
      while a < middle || b < end {
        if b >= end ||
          (
            a < middle &&
            solution_compare(current[a], current[b], order, budget) <= 0
          ) {
          next.push(current[a])
          a += 1
        } else {
          next.push(current[b])
          b += 1
        }
      }
      start = end
    }
    current = next
    if width > n / 2 {
      break
    }
    width *= 2
  }
  current
}

///|
fn solution_variables(q : Query) -> Array[String] {
  if q.all {
    let names = Map([])
    q.group.variables(names)
    let result = names.keys().to_array()
    result.sort()
    result
  } else {
    q.projections.map(p => p.variable)
  }
}

///|
fn build_solutions(
  q : Query,
  input : Array[GroupedRow],
  budget : Budget,
) -> Array[Solution] raise QueryError {
  let variables = solution_variables(q)
  let solutions = []
  for item in input {
    let row = item.row
    let projected = Binding::empty()
    let source = row.copy()
    if q.all {
      for name in variables {
        budget.tick()
        if row.get(name) is Some(t) {
          projected.values[name] = t
        }
      }
    } else {
      for p in q.projections {
        let ctx = EvalContext::{ row: source, budget, group: item.members, }
        if p.expression.maybe(ctx) is Some(t) {
          projected.values[p.variable] = t
          source.values[p.variable] = t
        }
      }
    }
    let ctx = EvalContext::{ row: source, budget, group: item.members, }
    let keys = q.order.map(item => item.0.maybe(ctx))
    solutions.push({ source, projected, keys, })
  }
  let ordered = if q.order.length() == 0 {
    solutions
  } else {
    sort_solutions(solutions, q.order, budget)
  }
  let seen : Map[String, Bool] = Map([])
  let result = []
  let mut offset = q.offset
  for solution in ordered {
    if q.distinct {
      let key = solution.projected.key(variables)
      if seen.get(key) is Some(_) {
        continue
      }
      seen[key] = true
    }
    if offset > 0 {
      offset -= 1
      continue
    }
    match q.limit {
      Some(n) => if result.length() >= n { break }
      None => ()
    }
    if result.length() >= budget.limits.max_results {
      raise Resource("result rows")
    }
    result.push(solution)
  }
  result
}
