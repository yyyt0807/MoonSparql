///|
fn Budget::uuid_text(self : Budget) -> String raise QueryError {
  let first = (self.entropy_word() & 0xffffffffffff0fffUL) | 0x4000UL
  let second = (self.entropy_word() & 0x3fffffffffffffffUL) |
    0x8000000000000000UL
  let hex = "0123456789abcdef"
  let output = StringBuilder()
  for i = 0; i < 32; i = i + 1 {
    if i == 8 || i == 12 || i == 16 || i == 20 {
      output.write_char('-')
    }
    let word = if i < 16 { first } else { second }
    let shift = (15 - i % 16) * 4
    output.write_char(
      hex[((word >> shift) & 15UL).to_int()].to_int().unsafe_to_char(),
    )
  }
  let value = output.to_string()
  if self.issued_uuids.contains(value) {
    raise Evaluation("host entropy produced a repeated UUID")
  }
  self.issued_uuids[value] = true
  value
}

///|
fn Budget::uuid_term(self : Budget) -> Term raise QueryError {
  iri("urn:uuid:" + self.uuid_text())
}
