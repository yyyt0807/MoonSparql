///|
pub struct Dataset {
  priv facts : Array[Quad]
  priv subjects : Map[String, Array[Int32]]
  priv predicates : Map[String, Array[Int32]]
  priv objects : Map[String, Array[Int32]]
  priv graphs : Map[String, Array[Int32]]
  priv names : Array[Term]
  priv declared_names : Array[Term]
}

///|
fn graph_key(g : Term?) -> String {
  match g {
    None => "D"
    Some(t) => t.key()
  }
}

///|
fn index_add(
  index : Map[String, Array[Int32]],
  key : String,
  position : Int32,
) -> Unit {
  match index.get(key) {
    Some(xs) => xs.push(position)
    None => index[key] = [position]
  }
}

///|
pub fn Dataset::from_quads(
  quads : Array[Quad],
  named_graphs~ : Array[Term] = [],
  limits~ : Limits = Limits::default(),
) -> Dataset raise QueryError {
  limits.validate()
  if quads.length() > limits.max_triples {
    raise Resource("input quads")
  }
  if named_graphs.length() > limits.max_triples {
    raise Resource("named graphs")
  }
  let facts : Array[Quad] = []
  let subjects = Map([])
  let predicates = Map([])
  let objects = Map([])
  let graphs = Map([])
  let names : Array[Term] = []
  let seen : Map[String, Bool] = Map([])
  let named : Map[String, Bool] = Map([])
  for name in named_graphs {
    if name.kind != IriKind {
      raise InvalidInput("named graph requires an IRI")
    }
    if !named.contains(name.key()) {
      named[name.key()] = true
      names.push(name)
      graphs[name.key()] = []
    }
  }
  let declared_names = names.copy()
  for q in quads {
    let key = q.key()
    if seen.get(key) is None {
      seen[key] = true
      let i = facts.length()
      facts.push(q)
      index_add(subjects, q.subject.key(), i)
      index_add(predicates, q.predicate.key(), i)
      index_add(objects, q.object.key(), i)
      index_add(graphs, graph_key(q.graph), i)
      match q.graph {
        Some(g) =>
          if named.get(g.key()) is None {
            named[g.key()] = true
            names.push(g)
          }
        None => ()
      }
    }
  }
  if names.length() > limits.max_triples {
    raise Resource("named graphs")
  }
  { facts, subjects, predicates, objects, graphs, names, declared_names, }
}

///|
pub fn Dataset::length(self : Dataset) -> Int32 {
  self.facts.length()
}

///|
pub fn Dataset::quads(self : Dataset) -> Array[Quad] {
  self.facts.copy()
}

///|
pub fn Dataset::graph_names(self : Dataset) -> Array[Term] {
  self.names.copy()
}

///|
fn Dataset::candidate_ids(
  self : Dataset,
  s : Term?,
  p : Term?,
  o : Term?,
  g : Term?,
) -> Array[Int32] {
  let mut best = self.graphs.get(graph_key(g)).unwrap_or([])
  for entry in [(s, self.subjects), (p, self.predicates), (o, self.objects)] {
    let (value, index) = entry
    match value {
      Some(t) => {
        let ids = index.get(t.key()).unwrap_or([])
        if ids.length() < best.length() {
          best = ids
        }
      }
      None => ()
    }
  }
  best
}

///|
fn matches_term(wanted : Term?, actual : Term) -> Bool {
  match wanted {
    None => true
    Some(t) => t == actual
  }
}

///|
fn Dataset::scan(
  self : Dataset,
  s : Term?,
  p : Term?,
  o : Term?,
  g : Term?,
  budget : Budget,
) -> Array[Quad] raise QueryError {
  let result = []
  for i in self.candidate_ids(s, p, o, g) {
    budget.tick()
    let q = self.facts[i]
    if q.graph == g &&
      matches_term(s, q.subject) &&
      matches_term(p, q.predicate) &&
      matches_term(o, q.object) {
      result.push(q)
      budget.rows(result.length())
    }
  }
  result
}

///|
pub fn Dataset::matching(
  self : Dataset,
  subject? : Term,
  predicate? : Term,
  object? : Term,
  graph? : Term,
  limits~ : Limits = Limits::default(),
) -> Array[Quad] raise QueryError {
  self.scan(subject, predicate, object, graph, Budget::new(limits))
}
