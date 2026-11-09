///|
fn bounded_path(
  data : Dataset,
  path : Path,
  graph : Term?,
  s : Term?,
  o : Term?,
  extras : Array[Term],
  budget : Budget,
) -> Array[(Term, Term)] raise QueryError {
  match path {
    ZeroMore(inner) | OneMore(inner) => {
      let zero = path is ZeroMore(_)
      if s is Some(start) {
        let include_zero = zero &&
          path_zero_node(data, graph, start, extras, budget)
        return path_closure(
          evaluate_path(data, inner, graph, extras, budget),
          [start],
          include_zero,
          budget,
        )
      }
      if o is Some(end) {
        let include_zero = zero &&
          path_zero_node(data, graph, end, extras, budget)
        let reverse = evaluate_path(data, inner, graph, extras, budget).map(p => {
          (p.1, p.0)
        })
        return path_closure(reverse, [end], include_zero, budget).map(p => {
          (p.1, p.0)
        })
      }
    }
    _ => ()
  }
  evaluate_path(data, path, graph, extras, budget)
}

///|
fn path_zero_node(
  data : Dataset,
  graph : Term?,
  node : Term,
  constants : Array[Term],
  budget : Budget,
) -> Bool raise QueryError {
  if constants.contains(node) {
    return true
  }
  for (s, o) in [(Some(node), None), (None, Some(node))] {
    for i in data.candidate_ids(s, None, o, graph) {
      budget.tick()
      let fact = data.facts[i]
      if fact.graph == graph &&
        matches_term(s, fact.subject) &&
        matches_term(o, fact.object) {
        return true
      }
    }
  }
  false
}

///|
fn join_property_path(
  data : Dataset,
  input : Array[Binding],
  subject : Slot,
  path : Path,
  object : Slot,
  graph : Term?,
  budget : Budget,
) -> Array[Binding] raise QueryError {
  let cache : Map[String, Array[(Term, Term)]] = Map([])
  let output = []
  let constants = []
  for slot in [subject, object] {
    if slot is Fixed(term) {
      constants.push(term)
    }
  }
  for row in input {
    let s = row.resolve(subject)
    let o = row.resolve(object)
    let skey = match s {
      Some(t) => "B" + key_part(t.key())
      None => "U"
    }
    let okey = match o {
      Some(t) => "B" + key_part(t.key())
      None => "U"
    }
    let key = skey + okey
    let pairs = match cache.get(key) {
      Some(pairs) => pairs
      None => {
        let pairs = bounded_path(data, path, graph, s, o, constants, budget)
        cache[key] = pairs
        pairs
      }
    }
    for (a, b) in pairs {
      budget.tick()
      if !matches_term(s, a) || !matches_term(o, b) {
        continue
      }
      let next = row.copy()
      if next.bind(subject, a) && next.bind(object, b) {
        output.push(next)
        budget.rows(output.length())
      }
    }
  }
  output
}
