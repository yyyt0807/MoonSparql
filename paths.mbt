///|
fn pair_push(
  pairs : Array[(Term, Term)],
  a : Term,
  b : Term,
  budget : Budget,
) -> Unit raise QueryError {
  budget.path()
  pairs.push((a, b))
}

///|
fn path_nodes(
  data : Dataset,
  graph : Term?,
  extra : Array[Term],
  budget : Budget,
) -> Array[Term] raise QueryError {
  let nodes = []
  let seen : Map[String, Bool] = Map([])
  for q in data.scan(None, None, None, graph, budget) {
    for t in [q.subject, q.object] {
      if seen.get(t.key()) is None {
        seen[t.key()] = true
        nodes.push(t)
      }
    }
  }
  for t in extra {
    if seen.get(t.key()) is None {
      seen[t.key()] = true
      nodes.push(t)
    }
  }
  nodes
}

///|
fn unique_pairs(
  pairs : Array[(Term, Term)],
  budget : Budget,
) -> Array[(Term, Term)] raise QueryError {
  let seen : Map[String, Bool] = Map([])
  let output = []
  for pair in pairs {
    budget.tick()
    let key = key_part(pair.0.key()) + pair.1.key()
    if seen.get(key) is None {
      seen[key] = true
      pair_push(output, pair.0, pair.1, budget)
    }
  }
  output
}

///|
fn path_closure(
  edges : Array[(Term, Term)],
  nodes : Array[Term],
  include_zero : Bool,
  budget : Budget,
) -> Array[(Term, Term)] raise QueryError {
  let adjacency : Map[String, Array[Term]] = Map([])
  for (a, b) in edges {
    budget.tick()
    match adjacency.get(a.key()) {
      Some(next) => next.push(b)
      None => adjacency[a.key()] = [b]
    }
  }
  let output = []
  for start in nodes {
    let seen : Map[String, Bool] = Map([])
    let queue = []
    let initial = if include_zero {
      [start]
    } else {
      adjacency.get(start.key()).unwrap_or([])
    }
    for first in initial {
      budget.tick()
      if !seen.contains(first.key()) {
        seen[first.key()] = true
        queue.push(first)
      }
    }
    let mut i = 0
    while i < queue.length() {
      budget.tick()
      let node = queue[i]
      i += 1
      pair_push(output, start, node, budget)
      for next in adjacency.get(node.key()).unwrap_or([]) {
        budget.tick()
        if seen.get(next.key()) is None {
          seen[next.key()] = true
          queue.push(next)
        }
      }
      // Pending edges, not just emitted pairs, are bounded.
      if queue.length() > budget.limits.max_steps {
        raise Resource("path traversal queue")
      }
    }
  }
  output
}

///|
fn negated_pairs(
  data : Dataset,
  graph : Term?,
  excluded : Array[Term],
  reverse : Bool,
  budget : Budget,
) -> Array[(Term, Term)] raise QueryError {
  let predicates = Map([])
  for term in excluded {
    budget.tick()
    predicates[term.key()] = true
  }
  let seen : Map[String, Bool] = Map([])
  let pairs = []
  for q in data.scan(None, None, None, graph, budget) {
    if predicates.contains(q.predicate.key()) {
      continue
    }
    let (a, b) = if reverse {
      (q.object, q.subject)
    } else {
      (q.subject, q.object)
    }
    let key = key_part(a.key()) + b.key()
    if !seen.contains(key) {
      seen[key] = true
      pair_push(pairs, a, b, budget)
    }
  }
  pairs
}

///|
fn evaluate_path(
  data : Dataset,
  path : Path,
  graph : Term?,
  extra : Array[Term],
  budget : Budget,
) -> Array[(Term, Term)] raise QueryError {
  budget.tick()
  match path {
    Predicate(p) => {
      let output = []
      for q in data.scan(None, Some(p), None, graph, budget) {
        pair_push(output, q.subject, q.object, budget)
      }
      output
    }
    PathVar(_) =>
      raise Unsupported(0, "variables inside composite property paths")
    Inverse(inner) =>
      evaluate_path(data, inner, graph, extra, budget).map(p => (p.1, p.0))
    Negated(forward, reverse) => {
      let pairs = if !forward.is_empty() || reverse.is_empty() {
        negated_pairs(data, graph, forward, false, budget)
      } else {
        []
      }
      if !reverse.is_empty() {
        pairs.append(negated_pairs(data, graph, reverse, true, budget))
      }
      pairs
    }
    Alternative(left, right) => {
      let a = evaluate_path(data, left, graph, extra, budget)
      let b = evaluate_path(data, right, graph, extra, budget)
      // Alternatives are a bag union; equal endpoints reached by two fixed
      // paths remain two matches, unlike arbitrary-length reachability.
      budget.rows(a.length() + b.length())
      a.append(b)
      a
    }
    Sequence(left, right) => {
      let a = evaluate_path(data, left, graph, extra, budget)
      let b = evaluate_path(data, right, graph, extra, budget)
      let index : Map[String, Array[Term]] = Map([])
      for (s, o) in b {
        match index.get(s.key()) {
          Some(items) => items.push(o)
          None => index[s.key()] = [o]
        }
      }
      let output = []
      for (s, middle) in a {
        for o in index.get(middle.key()).unwrap_or([]) {
          budget.tick()
          pair_push(output, s, o, budget)
        }
      }
      output
    }
    ZeroOne(inner) => {
      let edges = evaluate_path(data, inner, graph, extra, budget)
      for n in path_nodes(data, graph, extra, budget) {
        pair_push(edges, n, n, budget)
      }
      unique_pairs(edges, budget)
    }
    ZeroMore(inner) =>
      path_closure(
        evaluate_path(data, inner, graph, extra, budget),
        path_nodes(data, graph, extra, budget),
        true,
        budget,
      )
    OneMore(inner) =>
      path_closure(
        evaluate_path(data, inner, graph, extra, budget),
        path_nodes(data, graph, extra, budget),
        false,
        budget,
      )
  }
}
