///|
fn select_dataset(
  data : Dataset,
  sources : Array[(Term, Bool)],
  budget : Budget,
) -> Dataset raise QueryError {
  if sources.is_empty() {
    return data
  }
  let quads = []
  let names = []
  let selected : Map[(String, Bool), Bool] = Map([])
  let scope : BlankScope = { used: Map([]), mapping: Map([]), next: 0, budget, }
  // Fresh default-graph blanks must not collide with the retained named graphs.
  for q in data.facts {
    scope.remember(q.subject)
    scope.remember(q.object)
  }
  for (source, named) in sources {
    budget.tick()
    let key = source.key()
    if selected.contains((key, named)) {
      continue
    }
    selected[(key, named)] = true
    let ids = match data.graphs.get(key) {
      Some(ids) => ids
      None => raise InvalidInput("no local RDF source for " + source.lexical)
    }
    if named {
      names.push(source)
    }
    scope.mapping.clear()
    for id in ids {
      budget.tick()
      let q = data.facts[id]
      if quads.length() >= budget.limits.max_triples {
        raise Resource("selected dataset quads")
      }
      quads.push(
        if named {
          q
        } else {
          {
            ..q,
            graph: None,
            subject: scope.rename(q.subject),
            object: scope.rename(q.object),
          }
        },
      )
    }
  }
  Dataset::from_quads(quads, named_graphs=names, limits=budget.limits)
}

///|
/// Assemble a default Turtle document and explicitly named local documents.
/// Blank-node labels are scoped to each document, including empty named graphs.
pub fn Dataset::from_documents(
  default_graph : String,
  named_graphs : Array[(Term, String)],
  limits~ : Limits = Limits::default(),
) -> Dataset raise QueryError {
  let budget = Budget::new(limits)
  if named_graphs.length() > limits.max_triples ||
    default_graph.length() > limits.max_query_chars {
    raise Resource("dataset documents")
  }
  let mut units = default_graph.length()
  let declared : Map[String, Bool] = Map([])
  let names = []
  for (name, source) in named_graphs {
    budget.tick()
    if name.kind != IriKind || declared.contains(name.key()) {
      raise InvalidInput("duplicate or invalid named document IRI")
    }
    if source.length() > limits.max_query_chars - units {
      raise Resource("dataset document characters")
    }
    units += source.length()
    declared[name.key()] = true
    names.push(name)
  }
  let facts = Dataset::from_turtle(default_graph, limits~).facts.copy()
  let scope : BlankScope = { used: Map([]), mapping: Map([]), next: 0, budget, }
  for q in facts {
    scope.remember(q.subject)
    scope.remember(q.object)
  }
  for (name, source) in named_graphs {
    let document = Dataset::from_turtle(source, limits~)
    if document.length() > limits.max_triples - facts.length() {
      raise Resource("dataset document quads")
    }
    scope.mapping.clear()
    for q in document.facts {
      facts.push({
        ..q,
        graph: Some(name),
        subject: scope.rename(q.subject),
        object: scope.rename(q.object),
      })
    }
  }
  Dataset::from_quads(facts, named_graphs=names, limits~)
}
