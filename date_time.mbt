///|
fn date_time_function(name : String) -> Bool {
  ["YEAR", "MONTH", "DAY", "HOURS", "MINUTES", "SECONDS", "TIMEZONE", "TZ"].contains(
    name,
  )
}

///|
fn date_digits(
  chars : Array[Char],
  start : Int32,
  length : Int32,
) -> Int32 raise QueryError {
  let mut result = 0
  for i = start; i < start + length; i = i + 1 {
    let c = chars[i]
    if !digit(c) {
      raise Evaluation("invalid dateTime digits")
    }
    result = result * 10 + c.to_int() - '0'.to_int()
  }
  result
}

///|
fn date_time_part(
  name : String,
  term : Term,
  budget : Budget,
) -> Term raise QueryError {
  if term.kind != LiteralKind || term.datatype != xsd_namespace() + "dateTime" {
    raise Evaluation("xsd:dateTime required")
  }
  budget.tick(n=term.lexical.length())
  let chars = term.lexical.trim().to_owned().to_array()
  if chars.length() < 19 ||
    chars[4] != '-' ||
    chars[7] != '-' ||
    chars[10] != 'T' ||
    chars[13] != ':' ||
    chars[16] != ':' {
    raise Evaluation("expected four-digit dateTime year and time")
  }
  let year = date_digits(chars, 0, 4)
  let month = date_digits(chars, 5, 2)
  let day = date_digits(chars, 8, 2)
  let hour = date_digits(chars, 11, 2)
  let minute = date_digits(chars, 14, 2)
  let second = date_digits(chars, 17, 2)
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let month_days = match month {
    2 => if leap { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
  if year == 0 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > month_days ||
    hour > 23 ||
    minute > 59 ||
    second > 59 {
    raise Evaluation("dateTime component out of range")
  }
  let mut end = 19
  if chars.get(end) == Some('.') {
    end += 1
    let start = end
    while chars.get(end) is Some(c) && digit(c) {
      end += 1
    }
    if end == start {
      raise Evaluation("empty dateTime fraction")
    }
  }
  let zone = String::from_array(chars[end:])
  let offset = if zone == "Z" {
    Some(0)
  } else if zone.is_empty() {
    None
  } else {
    let tz = zone.to_array()
    if tz.length() != 6 || (tz[0] != '+' && tz[0] != '-') || tz[3] != ':' {
      raise Evaluation("invalid dateTime timezone")
    }
    let h = date_digits(tz, 1, 2)
    let m = date_digits(tz, 4, 2)
    if h > 14 || m > 59 || (h == 14 && m != 0) {
      raise Evaluation("dateTime timezone out of range")
    }
    Some((h * 60 + m) * (if tz[0] == '-' { -1 } else { 1 }))
  }
  match name {
    "YEAR" => integer(year)
    "MONTH" => integer(month)
    "DAY" => integer(day)
    "HOURS" => integer(hour)
    "MINUTES" => integer(minute)
    "SECONDS" => {
      let digits = budget.limits.max_numeric_digits
      let value = typed_literal(
        String::from_array(chars[17:end]),
        xsd_namespace() + "decimal",
      )
      numeric(value, digits).term(digits)
    }
    "TZ" => literal(zone)
    _ => {
      guard offset is Some(total) else {
        raise Evaluation("dateTime has no timezone")
      }
      let absolute = if total < 0 { -total } else { total }
      let h = absolute / 60
      let m = absolute % 60
      let text = if total == 0 {
        "PT0S"
      } else {
        (if total < 0 { "-PT" } else { "PT" }) +
        (if h > 0 { h.to_string() + "H" } else { "" }) +
        (if m > 0 { m.to_string() + "M" } else { "" })
      }
      typed_literal(text, xsd_namespace() + "dayTimeDuration")
    }
  }
}
