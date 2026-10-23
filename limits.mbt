///|
pub(all) suberror QueryError {
  InvalidTerm(String)
  Syntax(Int32, String)
  Unsupported(Int32, String)
  Resource(String)
  Evaluation(String)
  InvalidInput(String)
} derive(@debug.Debug)

///|
pub fn QueryError::message(self : QueryError) -> String {
  match self {
    InvalidTerm(s) => "invalid RDF term: " + s
    Syntax(p, s) => "syntax at " + p.to_string() + ": " + s
    Unsupported(p, s) => "unsupported at " + p.to_string() + ": " + s
    Resource(s) => "resource limit: " + s
    Evaluation(s) => "evaluation: " + s
    InvalidInput(s) => "input: " + s
  }
}

///|
pub(all) struct Limits {
  max_triples : Int32
  max_query_chars : Int32
  max_tokens : Int32
  max_depth : Int32
  max_steps : Int32
  max_bindings : Int32
  max_results : Int32
  max_path_pairs : Int32
  max_numeric_digits : Int32
} derive(Eq, @debug.Debug)

///|
pub fn Limits::default() -> Limits {
  {
    max_triples: 100000,
    max_query_chars: 262144,
    max_tokens: 32768,
    max_depth: 64,
    max_steps: 5000000,
    max_bindings: 100000,
    max_results: 100000,
    max_path_pairs: 100000,
    max_numeric_digits: 256,
  }
}

///|
fn Limits::validate(self : Limits) -> Unit raise QueryError {
  let values = [
    self.max_triples,
    self.max_query_chars,
    self.max_tokens,
    self.max_depth,
    self.max_steps,
    self.max_bindings,
    self.max_results,
    self.max_path_pairs,
    self.max_numeric_digits,
  ]
  for n in values {
    if n <= 0 {
      raise InvalidInput("limits must be positive")
    }
  }
  if self.max_depth > 256 {
    raise InvalidInput("max_depth exceeds 256")
  }
  if self.max_numeric_digits > 4096 {
    raise InvalidInput("numeric digit budget exceeds 4096")
  }
}

///|
priv struct Budget {
  limits : Limits
  mut steps : Int32
  mut peak_bindings : Int32
  mut path_pairs : Int32
}

///|
fn Budget::new(limits : Limits) -> Budget raise QueryError {
  limits.validate()
  { limits, steps: 0, peak_bindings: 0, path_pairs: 0, }
}

///|
fn Budget::tick(self : Budget, n~ : Int32 = 1) -> Unit raise QueryError {
  if n < 0 || n > self.limits.max_steps - self.steps {
    raise Resource("execution steps")
  }
  self.steps += n
}

///|
fn Budget::rows(self : Budget, n : Int32) -> Unit raise QueryError {
  if n > self.limits.max_bindings {
    raise Resource("intermediate bindings")
  }
  if n > self.peak_bindings {
    self.peak_bindings = n
  }
}

///|
fn Budget::path(self : Budget) -> Unit raise QueryError {
  if self.path_pairs >= self.limits.max_path_pairs {
    raise Resource("property path pairs")
  }
  self.path_pairs += 1
}

///|
pub extend QueryError with @debug.Debug::{to_repr}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}
