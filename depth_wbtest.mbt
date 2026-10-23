///|
test "left-associative expressions cannot bypass depth budgets" {
  let terms = Array::make(1000, "1").join("+")
  assert_true(rejects(() => prepare("SELECT ("+terms+" AS ?n) {}")))
  let paths = Array::make(1000, "<urn:p>").join("/")
  assert_true(rejects(() => prepare("SELECT * {?s "+paths+" ?o}")))
}
