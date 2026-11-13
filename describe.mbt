///|
fn describe_enqueue(
  resource : Term,
  pending : Array[Term],
  visited : Map[String, Bool],
  budget : Budget,
) -> Unit raise QueryError {
  budget.tick()
  if resource.kind == LiteralKind {
    return
  }
  let key = resource.key()
  if visited.get(key) is None {
    budget.rows(pending.length() + 1)
    visited[key] = true
    pending.push(resource)
  }
}

///|
fn describe_graph(
  data : Dataset,
  q : Query,
  solutions : Array[Solution],
  budget : Budget,
) -> Array[Quad] raise QueryError {
  let pending = []
  let visited = Map([])
  for slot in q.describe {
    if slot is Fixed(resource) {
      describe_enqueue(resource, pending, visited, budget)
    }
  }
  let variables = solution_variables(q)
  for solution in solutions {
    for name in variables {
      budget.tick()
      if solution.source.get(name) is Some(resource) {
        describe_enqueue(resource, pending, visited, budget)
      }
    }
  }
  let output = []
  for i = 0; i < pending.length(); i = i + 1 {
    let resource = pending[i]
    for q in data.scan(Some(resource), None, None, None, budget) {
      if output.length() >= budget.limits.max_results {
        raise Resource("description triples")
      }
      output.push(q)
      if q.object.kind == BlankKind {
        describe_enqueue(q.object, pending, visited, budget)
      }
    }
  }
  output
}
