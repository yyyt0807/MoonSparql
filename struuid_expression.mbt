///|
fn Budget::struuid_term(self : Budget) -> Term raise QueryError {
  literal(self.uuid_text())
}
