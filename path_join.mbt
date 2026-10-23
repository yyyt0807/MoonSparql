///|
fn bounded_path(data : Dataset, path : Path, graph : Term?, s : Term?, o : Term?,
  budget : Budget) -> Array[(Term, Term)] raise QueryError {
  let extras = []
  if s is Some(t) { extras.push(t) }
  if o is Some(t) { extras.push(t) }
  match path {
    ZeroMore(inner) | OneMore(inner) => {
      let zero = path is ZeroMore(_)
      if s is Some(start) {
        return path_closure(evaluate_path(data, inner, graph, extras, budget), [start], zero, budget)
      }
      if o is Some(end) {
        let reverse = evaluate_path(data, inner, graph, extras, budget).map(p => (p.1, p.0))
        return path_closure(reverse, [end], zero, budget).map(p => (p.1, p.0))
      }
    }
    _ => ()
  }
  evaluate_path(data, path, graph, extras, budget)
}

///|
fn join_property_path(data : Dataset, input : Array[Binding], subject : Slot,
  path : Path, object : Slot, graph : Term?, budget : Budget) -> Array[Binding] raise QueryError {
  let cache : Map[String, Array[(Term, Term)]] = {}
  let output = []
  for row in input {
    let s = row.resolve(subject)
    let o = row.resolve(object)
    let skey = match s { Some(t) => "B" + key_part(t.key()); None => "U" }
    let okey = match o { Some(t) => "B" + key_part(t.key()); None => "U" }
    let key = skey + okey
    let pairs = match cache.get(key) {
      Some(pairs) => pairs
      None => {
        let pairs = bounded_path(data, path, graph, s, o, budget)
        cache[key] = pairs
        pairs
      }
    }
    for (a, b) in pairs {
      budget.tick()
      if !matches_term(s, a) || !matches_term(o, b) { continue }
      let next = row.copy()
      if next.bind(subject, a) && next.bind(object, b) {
        output.push(next)
        budget.rows(output.length())
      }
    }
  }
  output
}
