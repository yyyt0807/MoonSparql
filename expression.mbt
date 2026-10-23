///|
priv struct EvalContext { row : Binding; budget : Budget; group : Array[Binding]? }

///|
fn boolean(value : Bool) -> Term {
  { kind: LiteralKind, lexical: if value { "true" } else { "false" },
    datatype: xsd_namespace() + "boolean", language: None }
}

///|
fn integer(value : Int) -> Term {
  { kind: LiteralKind, lexical: value.to_string(), datatype: xsd_namespace()+"integer",
    language: None }
}

///|
fn numeric_type(t : Term) -> Bool {
  t.kind == LiteralKind && ["integer", "decimal", "double"].any(
    suffix => t.datatype == xsd_namespace() + suffix)
}

///|
fn ebv(t : Term, digits : Int) -> Bool raise QueryError {
  if t.kind != LiteralKind { raise Evaluation("term has no effective boolean value") }
  if t.datatype == xsd_namespace() + "boolean" {
    match t.lexical.trim_space().to_string() {
      "true" | "1" => true
      "false" | "0" => false
      _ => raise Evaluation("invalid boolean lexical form")
    }
  } else if t.datatype == xsd_namespace()+"string" || t.language is Some(_) {
    t.lexical.length() != 0
  } else if numeric_type(t) {
    match numeric(t, digits) {
      Exact(v, _, _) => !v.is_zero()
      Floating(v) => !v.is_nan() && v != 0.0
    }
  } else { raise Evaluation("unsupported effective boolean datatype") }
}

///|
fn value_equal(a : Term, b : Term, digits : Int) -> Bool raise QueryError {
  if numeric_type(a) && numeric_type(b) {
    numeric(a, digits).compare(numeric(b, digits)) == Some(0)
  } else if a.kind != LiteralKind || b.kind != LiteralKind { a == b }
  else if a.datatype == xsd_namespace()+"boolean" && b.datatype == a.datatype {
    ebv(a, digits) == ebv(b, digits)
  } else if a.datatype == xsd_namespace()+"string" || a.language is Some(_) {
    a.datatype == b.datatype && a.language == b.language && a.lexical == b.lexical
  } else if a == b { true }
  else { raise Evaluation("incomparable literal values") }
}

///|
fn value_compare(a : Term, b : Term, digits : Int) -> Int? raise QueryError {
  if numeric_type(a) && numeric_type(b) { numeric(a, digits).compare(numeric(b, digits)) }
  else if a.kind == LiteralKind && b.kind == LiteralKind &&
    a.datatype == xsd_namespace()+"string" && b.datatype == a.datatype {
    Some(a.lexical.compare(b.lexical))
  } else if a.datatype == xsd_namespace()+"boolean" && b.datatype == a.datatype {
    let x = ebv(a, digits)
    let y = ebv(b, digits)
    Some(if x == y { 0 } else if x { 1 } else { -1 })
  } else { raise Evaluation("values do not have an ordered comparison") }
}

///|
fn Expr::maybe(self : Expr, context : EvalContext) -> Term? raise QueryError {
  try Some(self.eval(context)) catch {
    Evaluation(_) => None
    e => raise e
  }
}

///|
fn Expr::truth(self : Expr, context : EvalContext) -> Bool? raise QueryError {
  try Some(ebv(self.eval(context), context.budget.limits.max_numeric_digits)) catch {
    Evaluation(_) => None
    e => raise e
  }
}

///|
fn Expr::eval(self : Expr, context : EvalContext) -> Term raise QueryError {
  let b = context.budget
  b.tick()
  match self {
    Constant(t) => t
    Reference(name) => match context.row.get(name) {
      Some(t) => t
      None => raise Evaluation("unbound variable " + name)
    }
    Unary(op, child) => {
      let value = child.eval(context)
      if op == "!" { boolean(!ebv(value, b.limits.max_numeric_digits)) }
      else if op == "+" { numeric(value, b.limits.max_numeric_digits).term(b.limits.max_numeric_digits) }
      else { numeric_op("*", numeric(value, b.limits.max_numeric_digits),
        Exact(@bigint.BigInt::from_int(-1), 0, false), b.limits.max_numeric_digits) }
    }
    Binary(op, left, right) => {
      if op == "&&" || op == "||" {
        let a = left.truth(context)
        if op == "&&" && a == Some(false) { return boolean(false) }
        if op == "||" && a == Some(true) { return boolean(true) }
        let c = right.truth(context)
        if op == "&&" && c == Some(false) { boolean(false) }
        else if op == "||" && c == Some(true) { boolean(true) }
        else if a is None || c is None { raise Evaluation("boolean operand error") }
        else { boolean(op == "&&") }
      } else {
        let a = left.eval(context)
        let c = right.eval(context)
        if ["+", "-", "*", "/"].contains(op) {
          b.tick(n=a.lexical.length() + c.lexical.length())
          numeric_op(op, numeric(a, b.limits.max_numeric_digits),
            numeric(c, b.limits.max_numeric_digits), b.limits.max_numeric_digits)
        } else if op == "=" || op == "!=" {
          let equal = value_equal(a, c, b.limits.max_numeric_digits)
          boolean(if op == "=" { equal } else { !equal })
        } else {
          let comparison = value_compare(a, c, b.limits.max_numeric_digits)
          boolean(match comparison {
            None => false
            Some(n) => match op {
              "<" => n < 0
              ">" => n > 0
              "<=" => n <= 0
              ">=" => n >= 0
              _ => raise Evaluation("invalid comparison")
            }
          })
        }
      }
    }
    Call(name, args) => evaluate_call(name, args, context)
    Aggregate(_, _, _) => raise Evaluation("aggregate outside grouping")
    Exists(_, _) => raise Evaluation("EXISTS needs graph execution")
  }
}

///|
fn string_value(t : Term) -> String raise QueryError {
  if t.kind != LiteralKind || (t.datatype != xsd_namespace()+"string" && t.language is None) {
    raise Evaluation("string literal required")
  }
  t.lexical
}

///|
fn string_result(text : String, original : Term) -> Term raise QueryError {
  match original.language { Some(lang) => language_literal(text, lang); None => literal(text) }
}

///|
fn compatible_strings(a : Term, b : Term) -> Unit raise QueryError {
  ignore(string_value(a)); ignore(string_value(b))
  if b.language is Some(_) && a.language != b.language {
    raise Evaluation("incompatible language tags")
  }
}

///|
fn evaluate_call(name : String, args : Array[Expr], ctx : EvalContext) -> Term raise QueryError {
  let digits = ctx.budget.limits.max_numeric_digits
  if name == "BOUND" {
    if args.length() != 1 { raise Evaluation("BOUND arity") }
    return match args[0] {
      Reference(v) => boolean(ctx.row.get(v) is Some(_))
      _ => raise Evaluation("BOUND requires variable")
    }
  }
  if name == "IF" {
    if args.length() != 3 { raise Evaluation("IF arity") }
    return if ebv(args[0].eval(ctx), digits) { args[1].eval(ctx) } else { args[2].eval(ctx) }
  }
  if name == "COALESCE" {
    for arg in args { if arg.maybe(ctx) is Some(t) { return t } }
    raise Evaluation("COALESCE has no value")
  }
  if name == "IN" {
    let value = args[0].eval(ctx)
    let mut error = false
    for i = 1; i < args.length(); i = i + 1 {
      let equal = try Some(value_equal(value, args[i].eval(ctx), digits)) catch {
        Evaluation(_) => None
        e => raise e
      }
      if equal == Some(true) { return boolean(true) }
      if equal is None { error = true }
    }
    if error { raise Evaluation("IN element error") }
    return boolean(false)
  }
  let values = args.map(arg => arg.eval(ctx))
  if name == "CONCAT" {
    let out = StringBuilder::new()
    let common = if values.length() == 0 { None } else { values[0].language }
    let mut same = true
    for t in values {
      out.write_string(string_value(t))
      if t.language != common { same = false }
    }
    return if same && common is Some(lang) { language_literal(out.to_string(), lang) }
      else { literal(out.to_string()) }
  }
  let binary = ["SAMETERM", "CONTAINS", "STRSTARTS", "STRENDS", "LANGMATCHES", "STRDT", "STRLANG"].contains(name)
  if values.length() != (if binary { 2 } else { 1 }) { raise Evaluation(name + " arity") }
  let a = values[0]
  if binary {
    let b = values[1]
    return match name {
      "SAMETERM" => boolean(a == b)
      "STRDT" => {
        if a.language is Some(_) || b.kind != IriKind { raise Evaluation("STRDT types") }
        typed_literal(string_value(a), b.lexical)
      }
      "STRLANG" => language_literal(string_value(a), string_value(b))
      "LANGMATCHES" => {
        let lang = string_value(a).to_lower()
        let range = string_value(b).to_lower()
        boolean(if range == "*" { lang.length() > 0 }
          else { lang == range || lang.has_prefix(range + "-") })
      }
      _ => {
        compatible_strings(a, b)
        boolean(match name {
          "CONTAINS" => a.lexical.contains(b.lexical)
          "STRSTARTS" => a.lexical.has_prefix(b.lexical)
          "STRENDS" => a.lexical.has_suffix(b.lexical)
          _ => raise Evaluation("unknown binary function")
        })
      }
    }
  }
  match name {
    "ISIRI" | "ISURI" => boolean(a.kind == IriKind)
    "ISBLANK" => boolean(a.kind == BlankKind)
    "ISLITERAL" => boolean(a.kind == LiteralKind)
    "ISNUMERIC" => {
      let valid = try { ignore(numeric(a, digits)); true } catch { Evaluation(_) => false; e => raise e }
      boolean(valid)
    }
    "STR" => if a.kind == BlankKind { raise Evaluation("STR of blank node") } else { literal(a.lexical) }
    "LANG" => if a.kind != LiteralKind { raise Evaluation("LANG requires literal") }
      else { literal(a.language.or("")) }
    "DATATYPE" => if a.kind != LiteralKind { raise Evaluation("DATATYPE requires literal") }
      else { iri(a.datatype) }
    "STRLEN" => integer(string_value(a).to_array().length())
    "LCASE" => string_result(string_value(a).to_lower(), a)
    "UCASE" => string_result(string_value(a).to_upper(), a)
    "ABS" | "CEIL" | "FLOOR" | "ROUND" => numeric_unary(name, numeric(a, digits)).term(digits)
    _ => raise Evaluation("unknown function " + name)
  }
}

///|
fn numeric_unary(name : String, value : Numeric) -> Numeric {
  match value {
    Floating(v) => Floating(match name {
      "ABS" => v.abs()
      "CEIL" => v.ceil()
      "FLOOR" => v.floor()
      _ => (v + 0.5).floor()
    })
    Exact(c, scale, decimal) => {
      if name == "ABS" { return Exact(big_abs(c), scale, decimal) }
      let divisor = pow10(scale)
      let mut q = c / divisor
      let remainder = c % divisor
      let negative = c < @bigint.BigInt::from_int(0)
      let one = @bigint.BigInt::from_int(1)
      if name == "FLOOR" && negative && !remainder.is_zero() { q -= one }
      if name == "CEIL" && !negative && !remainder.is_zero() { q += one }
      if name == "ROUND" {
        let cmp = (big_abs(remainder) * @bigint.BigInt::from_int(2)).compare(divisor)
        if (!negative && cmp >= 0) || (negative && cmp > 0) {
          q += if negative { -one } else { one }
        }
      }
      Exact(q, 0, decimal)
    }
  }
}
