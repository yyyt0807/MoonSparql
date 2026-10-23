///|
fn[T] rejects(f : () -> T raise QueryError) -> Bool {
  try { ignore(f()); false } catch { _ => true }
}
