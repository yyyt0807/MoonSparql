///|
priv struct BlankScope {
  used : Map[String, Bool]
  mapping : Map[String, Term]
  mut next : Int32
  budget : Budget
}

///|
fn BlankScope::remember(
  self : BlankScope,
  term : Term,
) -> Unit raise QueryError {
  self.budget.tick()
  if term.kind == BlankKind {
    self.used[term.lexical] = true
  }
}

///|
fn BlankScope::rename(self : BlankScope, term : Term) -> Term raise QueryError {
  self.budget.tick()
  if term.kind != BlankKind {
    return term
  }
  if self.mapping.get(term.lexical) is Some(value) {
    return value
  }
  while self.next < 2147483647 {
    self.budget.tick()
    let name = "merge" + self.next.to_string()
    self.next += 1
    if !self.used.contains(name) {
      let value = blank(name)
      self.used[name] = true
      self.mapping[term.lexical] = value
      return value
    }
  }
  raise Resource("blank scope identifiers")
}

///|
/// RDF merge of independently scoped documents: all right-hand blank nodes are
/// consistently renamed, ground quads deduplicate, named IRI graphs are retained.
pub fn Dataset::merge_scoped(
  self : Dataset,
  other : Dataset,
  limits~ : Limits = Limits::default(),
) -> Dataset raise QueryError {
  let budget = Budget::new(limits)
  if self.facts.length() > limits.max_triples ||
    other.facts.length() > limits.max_triples - self.facts.length() {
    raise Resource("merge input quads")
  }
  let scope : BlankScope = { used: Map([]), mapping: Map([]), next: 0, budget, }
  for group in [self.facts, other.facts] {
    for q in group {
      scope.remember(q.subject)
      scope.remember(q.object)
    }
  }
  let facts = self.facts.copy()
  for q in other.facts {
    facts.push({
      ..q,
      subject: scope.rename(q.subject),
      object: scope.rename(q.object),
    })
  }
  Dataset::from_quads(facts, limits~)
}

///|
/// Align SELECT columns and append bags in source order, preserving duplicates
/// and unbound values. Independent right-side blank scope is the default.
/// Set shared_blank_scope only when both results originate from one RDF scope.
pub fn QueryResult::union_bindings(
  self : QueryResult,
  other : QueryResult,
  shared_blank_scope~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> QueryResult raise QueryError {
  let budget = Budget::new(limits)
  if self.answer is Some(_) ||
    other.answer is Some(_) ||
    !self.constructed.is_empty() ||
    !other.constructed.is_empty() ||
    self.variables.is_empty() ||
    other.variables.is_empty() {
    raise InvalidInput("union requires SELECT results with declared variables")
  }
  if self.bindings.length() > limits.max_results ||
    other.bindings.length() > limits.max_results - self.bindings.length() {
    raise Resource("union output rows")
  }
  budget.rows(self.bindings.length() + other.bindings.length())
  let names : Array[String] = []
  let declared : Map[String, Bool] = Map([])
  for group in [self.variables, other.variables] {
    for name in group {
      budget.tick()
      if !declared.contains(name) {
        if names.length() >= limits.max_tokens {
          raise Resource("union columns")
        }
        names.push(name)
        declared[name] = true
      }
    }
  }
  let scope : BlankScope = { used: Map([]), mapping: Map([]), next: 0, budget, }
  if !shared_blank_scope {
    for input in [self, other] {
      for row in input.bindings {
        for name in input.variables {
          budget.tick()
          if row.get(name) is Some(t) {
            scope.remember(t)
          }
        }
      }
    }
  }
  let rows : Array[Binding] = []
  for side, input in [self, other] {
    for row in input.bindings {
      let result = Binding::empty()
      for name in input.variables {
        budget.tick()
        if row.get(name) is Some(t) {
          result.values[name] = if side == 1 && !shared_blank_scope {
            scope.rename(t)
          } else {
            t
          }
        }
      }
      rows.push(result)
    }
  }
  {
    variables: names,
    bindings: rows,
    answer: None,
    constructed: [],
    stats: {
      steps: budget.steps,
      peak_bindings: budget.peak_bindings,
      path_pairs: 0,
    },
  }
}
