///|
priv enum Numeric {
  Exact(@bigint.BigInt, Int, Bool)
  Floating(Double)
}

///|
fn pow10(n : Int) -> @bigint.BigInt {
  let mut value = @bigint.BigInt::from_int(1)
  for i = 0; i < n; i = i + 1 { value = value * @bigint.BigInt::from_int(10) }
  value
}

///|
fn big_abs(value : @bigint.BigInt) -> @bigint.BigInt {
  if value < @bigint.BigInt::from_int(0) { -value } else { value }
}

///|
fn numeric(term : Term, digits : Int) -> Numeric raise QueryError {
  if term.kind != LiteralKind { raise Evaluation("numeric literal required") }
  let text = term.lexical.trim_space().to_string()
  if text.length() == 0 || text.length() > digits { raise Evaluation("numeric lexical budget") }
  let dt = term.datatype
  if dt == xsd_namespace() + "double" || dt == xsd_namespace() + "float" {
    let value = if text == "INF" || text == "+INF" { 1.0 / 0.0 }
      else if text == "-INF" { -1.0 / 0.0 }
      else if text == "NaN" { 0.0 / 0.0 }
      else {
        try @str.parse_double(text[:]) catch { _ => raise Evaluation("invalid floating literal") }
      }
    return Floating(value)
  }
  let decimal = dt == xsd_namespace() + "decimal"
  if !decimal && dt != xsd_namespace() + "integer" {
    raise Evaluation("unsupported numeric datatype")
  }
  let chars = text.to_array()
  let mut i = 0
  let mut negative = false
  if chars[0] == '+' || chars[0] == '-' { negative = chars[0] == '-'; i = 1 }
  let out = StringBuilder::new()
  let mut dot = false
  let mut scale = 0
  let mut count = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '.' && decimal && !dot { dot = true }
    else if digit(c) {
      out.write_char(c)
      count += 1
      if dot { scale += 1 }
    } else { raise Evaluation("invalid exact numeric literal") }
    i += 1
  }
  if count == 0 { raise Evaluation("numeric literal has no digits") }
  let coefficient = @bigint.BigInt::from_string(out.to_string())
  Exact(if negative { -coefficient } else { coefficient }, scale, decimal)
}

///|
fn Numeric::as_double(self : Numeric) -> Double raise QueryError {
  match self {
    Floating(v) => v
    Exact(_, _, _) => {
      let term = self.term(4096)
      try @str.parse_double(term.lexical[:]) catch { _ => raise Evaluation("numeric conversion") }
    }
  }
}

///|
fn Numeric::term(self : Numeric, digits : Int) -> Term raise QueryError {
  match self {
    Floating(v) => typed_literal(
      if v.is_nan() { "NaN" } else if v.is_pos_inf() { "INF" }
      else if v.is_neg_inf() { "-INF" } else { v.to_string() },
      xsd_namespace() + "double")
    Exact(coefficient, scale, decimal) => {
      let mut c = coefficient
      let mut s = scale
      let ten = @bigint.BigInt::from_int(10)
      while s > 0 && (c % ten).is_zero() { c = c / ten; s -= 1 }
      let raw = big_abs(c).to_string()
      if raw.length() > digits || s > digits { raise Resource("numeric result digits") }
      let text = StringBuilder::new()
      if c < @bigint.BigInt::from_int(0) { text.write_string("-") }
      if s == 0 {
        text.write_string(raw)
        if decimal { text.write_string(".0") }
      } else if s >= raw.length() {
        text.write_string("0.")
        for i = 0; i < s - raw.length(); i = i + 1 { text.write_string("0") }
        text.write_string(raw)
      } else {
        text.write_string(raw[0:raw.length() - s].to_string())
        text.write_string(".")
        text.write_string(raw[raw.length() - s:].to_string())
      }
      typed_literal(text.to_string(), xsd_namespace() + (if decimal { "decimal" } else { "integer" }))
    }
  }
}

///|
fn Numeric::compare(self : Numeric, other : Numeric) -> Int? raise QueryError {
  match (self, other) {
    (Exact(a, sa, _), Exact(b, sb, _)) => {
      let scale = if sa > sb { sa } else { sb }
      Some((a * pow10(scale - sa)).compare(b * pow10(scale - sb)))
    }
    _ => {
      let a = self.as_double()
      let b = other.as_double()
      if a.is_nan() || b.is_nan() { None }
      else if a < b { Some(-1) } else if a > b { Some(1) } else { Some(0) }
    }
  }
}

///|
fn numeric_op(op : String, left : Numeric, right : Numeric, digits : Int)
  -> Term raise QueryError {
  let result = match (left, right) {
    (Exact(a, sa, da), Exact(b, sb, db)) => {
      let scale = if sa > sb { sa } else { sb }
      match op {
        "+" => Exact(a * pow10(scale - sa) + b * pow10(scale - sb), scale, da || db)
        "-" => Exact(a * pow10(scale - sa) - b * pow10(scale - sb), scale, da || db)
        "*" => Exact(a * b, sa + sb, da || db)
        "/" => {
          if b.is_zero() { raise Evaluation("division by zero") }
          let numerator = a * pow10(sb + 24)
          let denominator = b * pow10(sa)
          let mut quotient = numerator / denominator
          let remainder = big_abs(numerator % denominator)
          let half = (remainder * @bigint.BigInt::from_int(2)).compare(big_abs(denominator))
          if half > 0 || (half == 0 && !(quotient % @bigint.BigInt::from_int(2)).is_zero()) {
            quotient += if (a < @bigint.BigInt::from_int(0)) ==
              (b < @bigint.BigInt::from_int(0)) { @bigint.BigInt::from_int(1) }
              else { @bigint.BigInt::from_int(-1) }
          }
          Exact(quotient, 24, true)
        }
        _ => raise Evaluation("unknown arithmetic operator")
      }
    }
    _ => {
      let a = left.as_double()
      let b = right.as_double()
      Floating(match op {
        "+" => a + b
        "-" => a - b
        "*" => a * b
        "/" => a / b
        _ => raise Evaluation("unknown arithmetic operator")
      })
    }
  }
  result.term(digits)
}
