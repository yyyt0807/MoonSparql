///|
priv struct Construction {
  used : Map[String, Bool]
  mut serial : Int
}

///|
fn Construction::fresh(self : Construction, budget : Budget) -> Term raise QueryError {
  while true {
    budget.tick()
    if self.serial == 2147483647 { raise Resource("constructed blank node labels") }
    let label = "ms_construct_" + self.serial.to_string()
    self.serial += 1
    if self.used.get(label) is None {
      self.used[label] = true
      return blank(label)
    }
  } nobreak { raise Resource("constructed blank node labels") }
}

///|
fn template_term(slot : Slot, row : Binding, labels : Map[String, Term],
  state : Construction, budget : Budget) -> Term? raise QueryError {
  match slot {
    Variable(name) => row.get(name)
    Fixed(t) => if t.kind == BlankKind {
      match labels.get(t.lexical) {
        Some(fresh) => Some(fresh)
        None => {
          let fresh = state.fresh(budget)
          labels[t.lexical] = fresh
          Some(fresh)
        }
      }
    } else { Some(t) }
  }
}

///|
fn construct_graph(data : Dataset, solutions : Array[Solution],
  template : Array[(Slot, Path, Slot)], budget : Budget) -> Array[Quad] raise QueryError {
  let used : Map[String, Bool] = {}
  for q in data.facts {
    for t in [q.subject, q.object] { if t.kind == BlankKind { used[t.lexical] = true } }
  }
  for solution in solutions {
    for _, t in solution.source.values { if t.kind == BlankKind { used[t.lexical] = true } }
  }
  let state = Construction::{ used, serial: 0 }
  let output = []
  let seen : Map[String, Bool] = {}
  for solution in solutions {
    let labels : Map[String, Term] = {}
    for (s, p, o) in template {
      budget.tick()
      let subject = template_term(s, solution.source, labels, state, budget)
      let object = template_term(o, solution.source, labels, state, budget)
      let predicate = match p {
        Predicate(t) => Some(t)
        PathVar(name) => solution.source.get(name)
        _ => raise Unsupported(0, "paths in CONSTRUCT template")
      }
      match (subject, predicate, object) {
        (Some(s), Some(p), Some(o)) => {
          // SPARQL omits triples with unbound or illegal RDF positions.
          if s.kind == LiteralKind || p.kind != IriKind { continue }
          let q = quad(s, p, o)
          if seen.get(q.key()) is None {
            if output.length() >= budget.limits.max_results { raise Resource("constructed triples") }
            seen[q.key()] = true
            output.push(q)
          }
        }
        _ => ()
      }
    }
  }
  output
}
