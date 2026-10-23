///|
priv struct GroupedRow {
  row : Binding
  members : Array[Binding]?
}

///|
fn Expr::has_aggregate(self : Expr) -> Bool {
  match self {
    Aggregate(_, _, _) => true
    Unary(_, e) => e.has_aggregate()
    Binary(_, a, b) => a.has_aggregate() || b.has_aggregate()
    Call(_, args) => args.any(e => e.has_aggregate())
    _ => false
  }
}

///|
fn query_grouped(q : Query) -> Bool {
  q.group_by.length() > 0 ||
  q.projections.any(p => p.expression.has_aggregate()) ||
  q.having.any(e => e.has_aggregate()) ||
  q.order.any(o => o.0.has_aggregate())
}

///|
fn full_binding_key(row : Binding) -> String {
  let out = StringBuilder()
  for name in row.variables() {
    out.write_string(key_part(name))
    out.write_string(key_part(row.values.get(name).unwrap().key()))
  }
  out.to_string()
}

///|
fn aggregate_value(
  name : String,
  expression : Expr?,
  distinct : Bool,
  ctx : EvalContext,
) -> Term raise QueryError {
  let rows = match ctx.group {
    Some(rows) => rows
    None => raise Evaluation("aggregate outside group")
  }
  let seen : Map[String, Bool] = Map([])
  let values = []
  let mut count = 0
  for row in rows {
    ctx.budget.tick()
    let subcontext = EvalContext::{ row, budget: ctx.budget, group: None, }
    let value = match expression {
      None => None
      Some(e) =>
        if name == "COUNT" || name == "SAMPLE" {
          e.maybe(subcontext)
        } else {
          Some(e.eval(subcontext))
        }
    }
    if expression is Some(_) && value is None {
      continue
    }
    let key = match value {
      Some(v) => v.key()
      None => full_binding_key(row)
    }
    if distinct && seen.get(key) is Some(_) {
      continue
    }
    seen[key] = true
    count += 1
    if value is Some(v) {
      values.push(v)
    }
  }
  if name == "COUNT" {
    return integer(count)
  }
  if name == "SUM" || name == "AVG" {
    let mut total = integer(0)
    for value in values {
      ctx.budget.tick(n=value.lexical.length())
      total = numeric_op(
        "+",
        numeric(total, ctx.budget.limits.max_numeric_digits),
        numeric(value, ctx.budget.limits.max_numeric_digits),
        ctx.budget.limits.max_numeric_digits,
      )
    }
    if name == "SUM" {
      return total
    }
    if count == 0 {
      return integer(0)
    }
    return numeric_op(
      "/",
      numeric(total, ctx.budget.limits.max_numeric_digits),
      numeric(integer(count), ctx.budget.limits.max_numeric_digits),
      ctx.budget.limits.max_numeric_digits,
    )
  }
  if values.length() == 0 {
    raise Evaluation("empty aggregate")
  }
  let mut result = values[0]
  if name == "SAMPLE" {
    return result
  }
  for value in values {
    let cmp = order_terms(Some(value), Some(result), ctx.budget)
    if (name == "MIN" && cmp < 0) || (name == "MAX" && cmp > 0) {
      result = value
    }
  }
  result
}

///|
fn group_rows(
  q : Query,
  rows : Array[Binding],
  budget : Budget,
) -> Array[GroupedRow] raise QueryError {
  if !query_grouped(q) {
    return rows.map(row => { row, members: None, })
  }
  let indexes : Map[String, Int32] = Map([])
  let keys : Array[Binding] = []
  let members : Array[Array[Binding]] = []
  if q.group_by.length() == 0 {
    keys.push(Binding::empty())
    members.push(rows)
  } else {
    for row in rows {
      budget.tick()
      let key = StringBuilder()
      let binding = Binding::empty()
      for e in q.group_by {
        let value = e.maybe({ row, budget, group: None, })
        key.write_string(
          match value {
            Some(t) => "B" + key_part(t.key())
            None => "U"
          },
        )
        if e is Reference(name) && value is Some(t) {
          binding.values[name] = t
        }
      }
      let key = key.to_string()
      match indexes.get(key) {
        Some(i) => members[i].push(row)
        None => {
          indexes[key] = keys.length()
          keys.push(binding)
          members.push([row])
        }
      }
    }
  }
  let output = []
  for i, row in keys {
    let ctx = EvalContext::{ row, budget, group: Some(members[i]), }
    let mut accepted = true
    for expression in q.having {
      if expression.truth(ctx) != Some(true) {
        accepted = false
        break
      }
    }
    if accepted {
      output.push({ row, members: Some(members[i]), })
    }
  }
  output
}
