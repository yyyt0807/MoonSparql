///|
fn extended_string_function(name : String) -> Bool {
  ["SUBSTR", "STRBEFORE", "STRAFTER", "ENCODE_FOR_URI", "REGEX", "REPLACE"].contains(
    name,
  )
}

///|
fn simple_string(t : Term) -> String raise QueryError {
  if t.language is Some(_) {
    raise Evaluation("plain string required")
  }
  string_value(t)
}

///|
fn substring_position(
  t : Term,
  budget : Budget,
) -> @bigint.BigInt raise QueryError {
  match numeric(t, budget.limits.max_numeric_digits) {
    Exact(value, 0, false) => value
    _ => raise Evaluation("SUBSTR requires integer positions")
  }
}

///|
fn clamp_offset(value : @bigint.BigInt, size : Int32) -> Int32 {
  if value <= @bigint.BigInt::from_int(0) {
    0
  } else if value >= @bigint.BigInt::from_int(size) {
    size
  } else {
    value.to_int()
  }
}

///|
fn encode_for_uri(text : String, budget : Budget) -> String raise QueryError {
  let hex = "0123456789ABCDEF".to_array()
  let output = StringBuilder()
  for byte in @utf8.encode(text) {
    budget.tick()
    let code = byte.to_int()
    let c = code.unsafe_to_char()
    if digit(c) ||
      (c >= 'A' && c <= 'Z') ||
      (c >= 'a' && c <= 'z') ||
      c == '-' ||
      c == '.' ||
      c == '_' ||
      c == '~' {
      output.write_char(c)
    } else {
      output.write_char('%')
      output.write_char(hex[code / 16])
      output.write_char(hex[code % 16])
    }
  }
  output.to_string()
}

///|
fn compile_sparql_regex(
  pattern : String,
  flags : String,
  input_size : Int32,
  budget : Budget,
) -> @str.Regex raise QueryError {
  if pattern.length() > 256 {
    raise Resource("regex pattern characters")
  }
  if flags.to_array().any(c => c != 'i') {
    raise Evaluation("supported regex flag: i")
  }
  // The core engine is automata based. Reject unbounded compilation expansion
  // from counted repetition and charge a conservative input/pattern product.
  let mut escaped = false
  let mut in_class = false
  for c in pattern {
    if escaped {
      escaped = false
    } else if c == '\\' {
      escaped = true
    } else if c == '[' {
      in_class = true
    } else if c == ']' {
      in_class = false
    } else if !in_class && (c == '{' || c == '}') {
      raise Evaluation("counted repetition is outside the regex profile")
    }
  }
  let cost = (pattern.length() + 1).to_int64() * (input_size.to_int64() + 1L)
  if cost > budget.limits.max_steps.to_int64() {
    raise Resource("regex work")
  }
  budget.tick(n=cost.to_int())
  let source = if flags.is_empty() { pattern } else { "(?i:" + pattern + ")" }
  @str.Regex(source[:]) catch {
    _ => raise Evaluation("invalid regular expression")
  }
}

///|
priv enum ReplacementPart {
  ReplacementText(String)
  CaptureIndex(Int32)
}

///|
fn replacement_parts(text : String) -> Array[ReplacementPart] raise QueryError {
  let chars = text.to_array()
  let result = []
  let mut literal_text = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    i += 1
    if c == '$' {
      if i >= chars.length() || !digit(chars[i]) {
        raise Evaluation("invalid REPLACE capture reference")
      }
      result.push(ReplacementText(literal_text.to_string()))
      literal_text = StringBuilder()
      let mut group_index = 0
      while i < chars.length() && digit(chars[i]) {
        if group_index > 256 {
          raise Evaluation("REPLACE capture reference out of range")
        }
        group_index = group_index * 10 + chars[i].to_int() - '0'.to_int()
        i += 1
      }
      result.push(CaptureIndex(group_index))
    } else if c == '\\' {
      if i >= chars.length() || (chars[i] != '\\' && chars[i] != '$') {
        raise Evaluation("invalid REPLACE escape")
      }
      literal_text.write_char(chars[i])
      i += 1
    } else {
      literal_text.write_char(c)
    }
  }
  result.push(ReplacementText(literal_text.to_string()))
  result
}

///|
fn replace_matches(
  regex : @str.Regex,
  text : String,
  replacement : String,
  budget : Budget,
) -> String raise QueryError {
  if regex.execute(""[:]) is Some(_) {
    raise Evaluation("REPLACE pattern can match an empty string")
  }
  budget.tick(n=replacement.length())
  let parts = replacement_parts(replacement)
  let output = StringBuilder()
  let mut end = 0
  for matched in regex.find(text[:]) {
    let start = matched.before().length()
    let size = matched.content().length()
    if size == 0 {
      raise Evaluation("REPLACE pattern matched an empty string")
    }
    output.write_view(text[end:start])
    end = start + size
    for part in parts {
      budget.tick()
      let fragment = match part {
        ReplacementText(value) => value[:]
        CaptureIndex(index) =>
          if index == 0 {
            matched.content()
          } else {
            matched.group(index).unwrap_or(""[:])
          }
      }
      budget.tick(n=fragment.length())
      output.write_view(fragment)
    }
  }
  output.write_view(text[end:])
  output.to_string()
}

///|
fn evaluate_string_function(
  name : String,
  values : Array[Term],
  budget : Budget,
) -> Term raise QueryError {
  let (minimum, maximum) = match name {
    "SUBSTR" | "REGEX" => (2, 3)
    "REPLACE" => (3, 4)
    "ENCODE_FOR_URI" => (1, 1)
    _ => (2, 2)
  }
  if values.length() < minimum || values.length() > maximum {
    raise Evaluation(name + " arity")
  }
  let first = values[0]
  let text = string_value(first)
  budget.tick(n=text.length())
  match name {
    "SUBSTR" => {
      let chars = text.to_array()
      let start = substring_position(values[1], budget) -
        @bigint.BigInt::from_int(1)
      let from = clamp_offset(start, chars.length())
      let to = if values.length() == 3 {
        clamp_offset(
          start + substring_position(values[2], budget),
          chars.length(),
        )
      } else {
        chars.length()
      }
      string_result(
        if to <= from {
          ""
        } else {
          String::from_array(chars[from:to])
        },
        first,
      )
    }
    "STRBEFORE" | "STRAFTER" => {
      let second = values[1]
      compatible_strings(first, second)
      budget.tick(n=second.lexical.length())
      if second.lexical.is_empty() {
        return string_result(if name == "STRBEFORE" { "" } else { text }, first)
      }
      match text.split_once(second.lexical) {
        Some((left, right)) =>
          string_result(
            (if name == "STRBEFORE" { left } else { right }).to_owned(),
            first,
          )
        None => literal("")
      }
    }
    "ENCODE_FOR_URI" => literal(encode_for_uri(text, budget))
    _ => {
      let pattern = simple_string(values[1])
      let flags = if values.length() == maximum {
        simple_string(values[maximum - 1])
      } else {
        ""
      }
      let regex = compile_sparql_regex(pattern, flags, text.length(), budget)
      if name == "REGEX" {
        boolean(regex.execute(text[:]) is Some(_))
      } else {
        string_result(
          replace_matches(regex, text, simple_string(values[2]), budget),
          first,
        )
      }
    }
  }
}
