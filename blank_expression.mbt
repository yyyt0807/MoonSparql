///|
fn Budget::fresh_query_blank(
  self : Budget,
  data : Dataset,
) -> Term raise QueryError {
  while true {
    self.tick()
    if self.blank_serial == 2147483647 {
      raise Resource("query blank node labels")
    }
    let node = blank("ms_query_" + self.blank_serial.to_string())
    self.blank_serial += 1
    let key = node.key()
    if !data.subjects.contains(key) && !data.objects.contains(key) {
      return node
    }
  } nobreak {
    raise Resource("query blank node labels")
  }
}
