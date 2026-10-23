///|
test "budget checks exact limits without wrapping addition" {
  let b = Budget::new({
    ..Limits::default(),
    max_steps: 3,
    max_bindings: 2,
    max_path_pairs: 1,
  })
  b.tick(n=3)
  assert_true(rejects(() => b.tick()))
  b.rows(2)
  assert_true(rejects(() => b.rows(3)))
  b.path()
  assert_true(rejects(() => b.path()))
}

///|
test "invalid budgets are rejected at entry" {
  assert_true(
    rejects(() => Budget::new({ ..Limits::default(), max_steps: 0, })),
  )
  assert_true(
    rejects(() => Budget::new({ ..Limits::default(), max_depth: 257, })),
  )
}
