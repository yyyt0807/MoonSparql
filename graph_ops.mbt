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
  row : Binding,
  group : Group,
  budget : Budget,
) -> Bool raise QueryError {
  let context = EvalContext::{ row, budget, group: None, }
  for pattern in group.patterns {
    if pattern is Filter(expression) && expression.truth(context) != Some(true) {
      return false
    }
  }
  true
}

///|
fn apply_filters(
  rows : Array[Binding],
  group : Group,
  budget : Budget,
) -> Array[Binding] raise QueryError {
  let output = []
  for row in rows {
    if passes_filters(row, group, budget) {
      output.push(row)
    }
  }
  output
}

///|
fn optional_join(
  data : Dataset,
  left : Array[Binding],
  group : Group,
  graph : Term?,
  budget : Budget,
) -> Array[Binding] raise QueryError {
  // FILTER directly inside OPTIONAL is the LeftJoin condition. Nested filters
  // retain their own scope and must not accidentally capture outer bindings.
  let body = Group::{ patterns: group.patterns.filter(p => !(p is Filter(_))), }
  let right = evaluate_group(data, body, [Binding::empty()], graph, budget)
  let output = []
  for a in left {
    let mut matched = false
    for b in right {
      budget.tick()
      if a.merge(b) is Some(row) && passes_filters(row, group, budget) {
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
  data : Dataset,
  left : Array[Binding],
  slot : Slot,
  group : Group,
  budget : Budget,
) -> Array[Binding] raise QueryError {
  let output = []
  for name in data.names {
    match slot {
      Fixed(t) => if t != name { continue }
      _ => ()
    }
    let right = evaluate_group(
      data,
      group,
      [Binding::empty()],
      Some(name),
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
