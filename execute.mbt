///|
#derive(Eq, @debug.Debug)
pub(all) struct ExecutionStats {
  steps : Int32
  peak_bindings : Int32
  path_pairs : Int32
}

///|
pub struct QueryResult {
  priv variables : Array[String]
  priv bindings : Array[Binding]
  priv answer : Bool?
  priv constructed : Array[Quad]
  priv stats : ExecutionStats
}

///|
pub fn QueryResult::variables(self : QueryResult) -> Array[String] {
  self.variables.copy()
}

///|
pub fn QueryResult::rows(self : QueryResult) -> Array[Binding] {
  self.bindings.copy()
}

///|
pub fn QueryResult::answer(self : QueryResult) -> Bool? {
  self.answer
}

///|
pub fn QueryResult::graph(self : QueryResult) -> Array[Quad] {
  self.constructed.copy()
}

///|
pub fn QueryResult::statistics(self : QueryResult) -> ExecutionStats {
  self.stats
}

///|
priv struct GraphContext {
  data : Dataset
  graph : Term?
  correlation : Binding?
  base_uri : String?
}

///|
fn GraphContext::slot(self : GraphContext, slot : Slot) -> Slot {
  if slot is Variable(name) &&
    self.correlation is Some(row) &&
    row.get(name) is Some(term) {
    Fixed(term)
  } else {
    slot
  }
}

///|
fn GraphContext::constrain(self : GraphContext, row : Binding) -> Binding? {
  guard self.correlation is Some(outer) else { return Some(row) }
  let result = Binding::empty()
  for name, term in row.values {
    if outer.get(name) is Some(expected) {
      if expected != term {
        return None
      }
    } else {
      result.values[name] = term
    }
  }
  Some(result)
}

///|
fn add_variable(names : Map[String, Bool], slot : Slot) -> Unit {
  match slot {
    Variable(name) if !name.has_prefix("\u0000") => names[name] = true
    _ => ()
  }
}

///|
fn Group::variables(self : Group, names : Map[String, Bool]) -> Unit {
  for pat in self.patterns {
    match pat {
      Triple(s, p, o) => {
        add_variable(names, s)
        add_variable(names, o)
        if p is PathVar(name) {
          names[name] = true
        }
      }
      Nested(g) | Optional(g) => g.variables(names)
      Union(groups) =>
        for g in groups {
          g.variables(names)
        }
      Graph(slot, g) => {
        add_variable(names, slot)
        g.variables(names)
      }
      Values(variables, _) =>
        for v in variables {
          names[v] = true
        }
      Bind(_, name) => names[name] = true
      Subselect(q) =>
        for name in solution_variables(q) {
          names[name] = true
        }
      Filter(_) | Minus(_) => ()
    }
  }
}

///|
fn join_triple(
  data : Dataset,
  input : Array[Binding],
  subject : Slot,
  path : Path,
  object : Slot,
  graph : Term?,
  budget : Budget,
) -> Array[Binding] raise QueryError {
  match path {
    Predicate(_) | PathVar(_) => ()
    _ =>
      return join_property_path(
        data, input, subject, path, object, graph, budget,
      )
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
      if next.bind(subject, q.subject) &&
        next.bind(pslot, q.predicate) &&
        next.bind(object, q.object) {
        output.push(next)
        budget.rows(output.length())
      }
    }
  }
  output
}

///|
fn evaluate_group(
  active : GraphContext,
  group : Group,
  input : Array[Binding],
  budget : Budget,
) -> Array[Binding] raise QueryError {
  let mut rows = input
  for pattern in group.patterns {
    budget.tick()
    rows = match pattern {
      Triple(s, p, o) => {
        let p = if p is PathVar(name) &&
          active.slot(Variable(name)) is Fixed(term) {
          Path::Predicate(term)
        } else {
          p
        }
        join_triple(
          active.data,
          rows,
          active.slot(s),
          p,
          active.slot(o),
          active.graph,
          budget,
        )
      }
      Nested(g) =>
        compatible_join(
          rows,
          evaluate_group(active, g, [Binding::empty()], budget),
          budget,
        )
      Optional(g) => optional_join(active, rows, g, budget)
      Filter(_) => rows
      Bind(expression, name) => {
        if active.slot(Variable(name)) is Fixed(_) {
          raise Unsupported(0, "BIND of a correlated EXISTS variable")
        }
        let output = []
        for row in rows {
          let next = row.copy()
          if next.get(name) is Some(_) {
            raise Evaluation("BIND variable already in scope")
          }
          if expression.maybe({ row, budget, group: None, active, })
            is Some(value) {
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
          let alternatives = evaluate_group(
            active,
            g,
            [Binding::empty()],
            budget,
          )
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
            if cells[i] is Some(t) {
              binding.values[name] = t
            }
          }
          if active.constrain(binding) is Some(row) {
            right.push(row)
          }
        }
        compatible_join(rows, right, budget)
      }
      Graph(slot, g) =>
        named_graph_join(active, rows, active.slot(slot), g, budget)
      Minus(g) =>
        minus_join(
          rows,
          evaluate_group(active, g, [Binding::empty()], budget),
          budget,
        )
      Subselect(q) => {
        let inner = execute_solutions(
          { ..active, correlation: None, },
          q,
          budget,
          nested=true,
        )
        let right = []
        for solution in inner {
          if active.constrain(solution.projected) is Some(binding) {
            right.push(binding)
          }
        }
        compatible_join(rows, right, budget)
      }
    }
  }
  apply_filters(active, rows, group, budget)
}

///|
fn execute_solutions(
  active : GraphContext,
  q : Query,
  budget : Budget,
  nested~ : Bool = false,
) -> Array[Solution] raise QueryError {
  let active = { ..active, base_uri: q.base_uri, }
  let rows = evaluate_group(active, q.group, [Binding::empty()], budget)
  let grouped = group_rows(active, q, rows, budget)
  if q.trailing.patterns.is_empty() {
    return build_solutions(active, q, grouped, budget, nested~)
  }
  let trailing = evaluate_group(active, q.trailing, [Binding::empty()], budget)
  let joined = []
  for item in grouped {
    for value in trailing {
      budget.tick()
      if item.row.merge(value) is Some(row) {
        joined.push({ row, members: item.members, })
        budget.rows(joined.length())
      }
    }
  }
  build_solutions(active, q, joined, budget, nested~)
}

///|
pub fn PreparedQuery::execute(
  self : PreparedQuery,
  data : Dataset,
) -> QueryResult raise QueryError {
  let budget = Budget::new(self.limits)
  let q = self.query
  if data.length() > self.limits.max_triples ||
    data.names.length() > self.limits.max_triples {
    raise Resource("dataset size")
  }
  let data = select_dataset(data, q.datasets, budget)
  let active = GraphContext::{
    data,
    graph: None,
    correlation: None,
    base_uri: q.base_uri,
  }
  let solutions = execute_solutions(active, q, budget)
  let constructed = match q.form {
    Construct => construct_graph(data, solutions, q.template, budget)
    Describe => describe_graph(data, q, solutions, budget)
    _ => []
  }
  {
    variables: if q.form == Select {
      solution_variables(q)
    } else {
      []
    },
    bindings: if q.form == Select {
      solutions.map(s => s.projected)
    } else {
      []
    },
    answer: if q.form == Ask {
      Some(solutions.length() > 0)
    } else {
      None
    },
    constructed,
    stats: {
      steps: budget.steps,
      peak_bindings: budget.peak_bindings,
      path_pairs: budget.path_pairs,
    },
  }
}

///|
pub extend ExecutionStats with Eq::{equal, not_equal}

///|
pub extend ExecutionStats with @debug.Debug::{to_repr}
