///|
test "scope validation rejects unbound rebinds before evaluation" {
  for source in ["SELECT * {VALUES ?x {UNDEF} BIND(1 AS ?x)}",
    "SELECT (1 AS ?x) {VALUES ?x {UNDEF}}",
    "SELECT ?x (COUNT(*) AS ?n) {VALUES ?x {1 2}}",
    "SELECT (SUM(COUNT(*)) AS ?n) {}",
    "SELECT * {FILTER(COUNT(*)>1)}"] {
    assert_true(rejects(() => prepare(source)))
  }
  assert_eq(prepare("SELECT (1 AS ?a) (?a+1 AS ?b) {}").form(), "SELECT")
}
