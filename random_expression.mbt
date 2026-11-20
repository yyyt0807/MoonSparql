///|
fn Budget::entropy_word(self : Budget) -> UInt64 raise QueryError {
  self.tick()
  guard self.entropy is Some(next) else {
    raise Evaluation("random expressions require host entropy")
  }
  next()
}

///|
fn Budget::random_term(self : Budget) -> Term raise QueryError {
  let value = (self.entropy_word() >> 11).to_double() / 9007199254740992.0
  Floating(value).term(self.limits.max_numeric_digits)
}
