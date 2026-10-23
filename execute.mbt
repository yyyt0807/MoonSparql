///|
pub(all) struct ExecutionStats {
  steps : Int
  peak_bindings : Int
  path_pairs : Int
} derive(Eq, @debug.Debug)

///|
pub struct QueryResult {
  priv variables : Array[String]
  priv bindings : Array[Binding]
  priv answer : Bool?
  priv constructed : Array[Quad]
  priv stats : ExecutionStats
}

///|
pub fn QueryResult::variables(self : QueryResult) -> Array[String] { self.variables.copy() }

///|
pub fn QueryResult::rows(self : QueryResult) -> Array[Binding] { self.bindings.copy() }

///|
pub fn QueryResult::answer(self : QueryResult) -> Bool? { self.answer }

///|
pub fn QueryResult::graph(self : QueryResult) -> Array[Quad] { self.constructed.copy() }

///|
pub fn QueryResult::statistics(self : QueryResult) -> ExecutionStats { self.stats }

///|
fn add_variable(names : Map[String, Bool], slot : Slot) -> Unit {
  match slot { Variable(name) => names[name] = true; _ => () }
}

///|
fn Group::variables(self : Group, names : Map[String, Bool]) -> Unit {
  for pat in self.patterns {
    match pat {
      Triple(s, p, o) => {
        add_variable(names, s); add_variable(names, o)
        if p is PathVar(name) { names[name] = true }
      }
      Nested(g) | Optional(g) => g.variables(names)
      Union(groups) => for g in groups { g.variables(names) }
      Graph(slot, g) => { add_variable(names, slot); g.variables(names) }
      Values(variables, _) => for v in variables { names[v] = true }
      Bind(_, name) => names[name] = true
      Filter(_) | Minus(_) => ()
    }
  }
}

///|
fn join_triple(data : Dataset, input : Array[Binding], subject : Slot,
  path : Path, object : Slot, graph : Term?, budget : Budget) -> Array[Binding] raise QueryError {
  match path {
    Predicate(_) | PathVar(_) => ()
    _ => return join_property_path(data, input, subject, path, object, graph, budget)
  }
  let pslot = match path {
    Predicate(p) => Fixed(p)
    PathVar(name) => Variable(name)
    _ => raise Unsupported(0, "property path execution")
  }
  let output = []
  for row in input {
    budget.tick()
    let s = row.resolve(subject)
    let p = row.resolve(pslot)
    let o = row.resolve(object)
    for q in data.scan(s, p, o, graph, budget) {
      let next = row.copy()
      if next.bind(subject, q.subject) && next.bind(pslot, q.predicate) &&
        next.bind(object, q.object) {
        output.push(next)
        budget.rows(output.length())
      }
    }
  }
  output
}

///|
fn evaluate_group(data : Dataset, group : Group, input : Array[Binding],
  graph : Term?, budget : Budget) -> Array[Binding] raise QueryError {
  let mut rows = input
  for pattern in group.patterns {
    rows = match pattern {
      Triple(s, p, o) => join_triple(data, rows, s, p, o, graph, budget)
      Nested(g) => compatible_join(rows,
        evaluate_group(data, g, [Binding::empty()], graph, budget), budget)
      Optional(g) => optional_join(data, rows, g, graph, budget)
      Filter(_) => rows
      Bind(expression, name) => {
        let output = []
        for row in rows {
          let next = row.copy()
          if next.get(name) is Some(_) { raise Evaluation("BIND variable already in scope") }
          if expression.maybe({ row, budget, group: None }) is Some(value) {
            next.values[name] = value
          }
          output.push(next)
          budget.rows(output.length())
        }
        output
      }
      Union(groups) => {
        let right = []
        for g in groups {
          let alternatives = evaluate_group(data, g, [Binding::empty()], graph, budget)
          budget.rows(right.length() + alternatives.length())
          right.append(alternatives)
        }
        compatible_join(rows, right, budget)
      }
      Values(names, table) => {
        let right = []
        for cells in table {
          let binding = Binding::empty()
          for i, name in names {
            if cells[i] is Some(t) { binding.values[name] = t }
          }
          right.push(binding)
        }
        compatible_join(rows, right, budget)
      }
      Graph(slot, g) => named_graph_join(data, rows, slot, g, budget)
      Minus(g) => minus_join(rows,
        evaluate_group(data, g, [Binding::empty()], graph, budget), budget)
    }
  }
  apply_filters(rows, group, budget)
}

///|
pub fn PreparedQuery::execute(self : PreparedQuery, data : Dataset)
  -> QueryResult raise QueryError {
  let budget = Budget::new(self.limits)
  let q = self.query
  if data.size() > self.limits.max_triples { raise Resource("dataset quads") }
  let rows = evaluate_group(data, q.group, [Binding::empty()], None, budget)
  let solutions = build_solutions(q, group_rows(q, rows, budget), budget)
  if q.form == Construct { raise Unsupported(0, "CONSTRUCT execution") }
  { variables: solution_variables(q),
    bindings: if q.form == Select { solutions.map(s => s.projected) } else { [] },
    answer: if q.form == Ask { Some(solutions.length() > 0) } else { None },
    constructed: [], stats: { steps: budget.steps, peak_bindings: budget.peak_bindings,
      path_pairs: budget.path_pairs } }
}
