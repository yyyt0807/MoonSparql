///|
fn compatible_join(
  left : Array[Binding],
  right : Array[Binding],
  budget : Budget,
) -> Array[Binding] raise QueryError {
  let output = []
  for a in left {
    for b in right {
      budget.tick()
      if a.merge(b) is Some(row) {
        output.push(row)
        budget.rows(output.length())
      }
    }
  }
  output
}

///|
fn passes_filters(
  active : GraphContext,
  row : Binding,
  filters : Array[Expr],
  budget : Budget,
) -> Bool raise QueryError {
  let context = EvalContext::{ row, budget, group: None, active, }
  for expression in filters {
    if expression.truth(context) != Some(true) {
      return false
    }
  }
  true
}

///|
fn Group::filters(self : Group) -> Array[Expr] {
  let filters = []
  for pattern in self.patterns {
    if pattern is Filter(expression) {
      filters.push(expression)
    }
  }
  filters
}

///|
fn apply_filters(
  active : GraphContext,
  rows : Array[Binding],
  group : Group,
  budget : Budget,
) -> Array[Binding] raise QueryError {
  let filters = group.filters()
  if filters.is_empty() {
    return rows
  }
  let output = []
  for row in rows {
    if passes_filters(active, row, filters, budget) {
      output.push(row)
    }
  }
  output
}

///|
fn optional_join(
  active : GraphContext,
  left : Array[Binding],
  group : Group,
  budget : Budget,
) -> Array[Binding] raise QueryError {
  // FILTER directly inside OPTIONAL is the LeftJoin condition. Nested filters
  // retain their own scope and must not accidentally capture outer bindings.
  let body = Group::{ patterns: group.patterns.filter(p => !(p is Filter(_))), }
  let right = evaluate_group(active, body, [Binding::empty()], budget)
  let filters = group.filters()
  let output = []
  for a in left {
    let mut matched = false
    for b in right {
      budget.tick()
      if a.merge(b) is Some(row) && passes_filters(active, row, filters, budget) {
        matched = true
        output.push(row)
        budget.rows(output.length())
      }
    }
    if !matched {
      output.push(a)
      budget.rows(output.length())
    }
  }
  output
}

///|
fn minus_join(
  left : Array[Binding],
  right : Array[Binding],
  budget : Budget,
) -> Array[Binding] raise QueryError {
  let output = []
  for a in left {
    let mut removed = false
    for b in right {
      budget.tick()
      let shared = a.values.keys().any(name => b.get(name) is Some(_))
      if shared && a.merge(b) is Some(_) {
        removed = true
        break
      }
    }
    if !removed {
      output.push(a)
    }
  }
  output
}

///|
fn named_graph_join(
  active : GraphContext,
  left : Array[Binding],
  slot : Slot,
  group : Group,
  budget : Budget,
) -> Array[Binding] raise QueryError {
  let output = []
  for name in active.data.names {
    budget.tick()
    match slot {
      Fixed(t) => if t != name { continue }
      _ => ()
    }
    let right = evaluate_group(
      { ..active, graph: Some(name), },
      group,
      [Binding::empty()],
      budget,
    )
    let named = []
    for row in right {
      let next = row.copy()
      if next.bind(slot, name) {
        named.push(next)
      }
    }
    let joined = compatible_join(left, named, budget)
    budget.rows(output.length() + joined.length())
    output.append(joined)
  }
  output
}
