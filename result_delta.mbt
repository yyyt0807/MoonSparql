///|
pub(all) struct BindingDelta {
  added : Array[Binding]
  removed : Array[Binding]
  retained : Int32
}

///|
fn delta_binding_key(binding : Binding, names : Array[String]) -> String {
  let b = StringBuilder()
  for name in names {
    match binding.get(name) {
      None => b.write_string("U;")
      Some(term) => {
        let key = term.key()
        b.write_string(key.length().to_string() + ":" + key)
      }
    }
  }
  b.to_string()
}

///|
/// Bag-sensitive SELECT comparison: term identity, unbound values and duplicate
/// occurrence counts matter; ordering does not. Blank node IDs must share scope.
pub fn QueryResult::binding_delta(
  self : QueryResult,
  newer : QueryResult,
  limits~ : Limits = Limits::default(),
) -> BindingDelta raise QueryError {
  let budget = Budget::new(limits)
  if self.answer is Some(_) ||
    newer.answer is Some(_) ||
    !self.constructed.is_empty() ||
    !newer.constructed.is_empty() ||
    self.variables.is_empty() ||
    newer.variables.is_empty() {
    raise InvalidInput(
      "binding delta requires SELECT results with declared variables",
    )
  }
  let names = self.variables.copy()
  let next_names = newer.variables.copy()
  names.sort()
  next_names.sort()
  if names != next_names {
    raise InvalidInput("result variable contracts differ")
  }
  if self.bindings.length() > limits.max_results ||
    newer.bindings.length() > limits.max_results {
    raise Resource("result delta input rows")
  }
  let counts : Map[String, Int32] = Map([])
  for row in self.bindings {
    budget.tick(n=names.length())
    let k = delta_binding_key(row, names)
    counts[k] = counts.get(k).unwrap_or(0) + 1
  }
  let added : Array[Binding] = []
  let removed : Array[Binding] = []
  let mut retained = 0
  for row in newer.bindings {
    budget.tick(n=names.length())
    let k = delta_binding_key(row, names)
    let count = counts.get(k).unwrap_or(0)
    if count > 0 {
      counts[k] = count - 1
      retained += 1
    } else {
      added.push(row)
    }
  }
  // Consume residual counts in old result order, retaining full original rows.
  for row in self.bindings {
    budget.tick(n=names.length())
    let k = delta_binding_key(row, names)
    let count = counts.get(k).unwrap_or(0)
    if count > 0 {
      if removed.length() >= limits.max_results - added.length() {
        raise Resource("result delta output rows")
      }
      removed.push(row)
      counts[k] = count - 1
    }
  }
  { added, removed, retained, }
}
