///|
/// Host-side exact patch, not SPARQL UPDATE. All preconditions are checked on
/// the original snapshot; failure leaves the dataset and its indexes unchanged.
pub fn Dataset::apply_patch(
  self : Dataset,
  remove : Array[Quad],
  add : Array[Quad],
  limits~ : Limits = Limits::default(),
) -> Dataset raise QueryError {
  let budget = Budget::new(limits)
  if self.facts.length() > limits.max_triples ||
    remove.length() > limits.max_triples ||
    add.length() > limits.max_triples {
    raise Resource("patch input quads")
  }
  let current : Map[String, Bool] = Map([])
  for q in self.facts {
    budget.tick()
    current[q.key()] = true
  }
  let deletions : Map[String, Bool] = Map([])
  for q in remove {
    budget.tick()
    let k = q.key()
    if !current.contains(k) || deletions.contains(k) {
      raise InvalidInput("missing or repeated patch removal")
    }
    deletions[k] = true
  }
  let additions : Map[String, Bool] = Map([])
  for q in add {
    budget.tick()
    let k = q.key()
    if current.contains(k) || deletions.contains(k) || additions.contains(k) {
      raise InvalidInput("existing or repeated patch addition")
    }
    additions[k] = true
  }
  let retained = self.facts.length() - remove.length()
  if add.length() > limits.max_triples - retained {
    raise Resource("patched dataset size")
  }
  let output : Array[Quad] = []
  for q in self.facts {
    budget.tick()
    if !deletions.contains(q.key()) {
      output.push(q)
    }
  }
  for q in add {
    output.push(q)
  }
  Dataset::from_quads(output, limits~)
}
