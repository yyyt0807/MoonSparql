///|
priv enum Lexeme {
  Word(String)
  Var(String)
  IriToken(String)
  StringToken(String)
  NumToken(String)
  Symbol(String)
  EndToken
} derive(Eq, @debug.Debug)

///|
priv struct Token { value : Lexeme; position : Int } derive(@debug.Debug)

///|
priv struct Lexer { chars : Array[Char]; mut i : Int }

///|
fn digit(c : Char) -> Bool { c >= '0' && c <= '9' }

///|
fn name_char(c : Char) -> Bool {
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || digit(c) ||
    c == '_' || c.to_int() >= 128
}

///|
fn space(c : Char) -> Bool { c == ' ' || c == '\t' || c == '\r' || c == '\n' }

///|
fn Lexer::peek(self : Lexer, delta? : Int = 0) -> Char? {
  self.chars.get(self.i + delta)
}

///|
fn Lexer::unicode(self : Lexer, width : Int) -> Char raise QueryError {
  let mut code = 0
  for j = 0; j < width; j = j + 1 {
    let c = match self.peek() {
      Some(c) => c
      None => raise Syntax(self.i, "truncated Unicode escape")
    }
    let n = c.to_int()
    let value = if n >= 48 && n <= 57 { n - 48 }
      else if n >= 65 && n <= 70 { n - 55 }
      else if n >= 97 && n <= 102 { n - 87 }
      else { raise Syntax(self.i, "non-hexadecimal escape") }
    if code > (0x10ffff - value) / 16 {
      raise Syntax(self.i, "Unicode scalar out of range")
    }
    code = code * 16 + value
    self.i += 1
  }
  if code >= 0xd800 && code <= 0xdfff {
    raise Syntax(self.i, "surrogate is not a Unicode scalar")
  }
  Char::from_int(code)
}

///|
fn Lexer::quoted(self : Lexer, quote : Char) -> String raise QueryError {
  let start = self.i
  let long = self.peek(delta=1) == Some(quote) && self.peek(delta=2) == Some(quote)
  self.i += if long { 3 } else { 1 }
  let text = StringBuilder::new()
  while self.i < self.chars.length() {
    let c = self.chars[self.i]
    if c == quote && (!long || (self.peek(delta=1) == Some(quote) &&
      self.peek(delta=2) == Some(quote))) {
      self.i += if long { 3 } else { 1 }
      return text.to_string()
    }
    if !long && (c == '\n' || c == '\r') {
      raise Syntax(self.i, "newline in short string")
    }
    self.i += 1
    if c != '\\' { text.write_char(c); continue }
    let escaped = match self.peek() {
      Some(e) => e
      None => raise Syntax(self.i, "truncated escape")
    }
    self.i += 1
    text.write_char(match escaped {
      't' => '\t'
      'b' => '\b'
      'n' => '\n'
      'r' => '\r'
      'f' => '\x0c'
      '"' => '"'
      '\'' => '\''
      '\\' => '\\'
      'u' => self.unicode(4)
      'U' => self.unicode(8)
      _ => raise Syntax(self.i - 1, "unknown string escape")
    })
  }
  raise Syntax(start, "unterminated string")
}

///|
fn Lexer::number(self : Lexer) -> String raise QueryError {
  let start = self.i
  while self.peek() is Some(c) && digit(c) { self.i += 1 }
  if self.peek() == Some('.') && self.peek(delta=1) is Some(after) &&
    (digit(after) || after == 'e' || after == 'E') {
    self.i += 1
    while self.peek() is Some(c) && digit(c) { self.i += 1 }
  }
  if self.peek() == Some('e') || self.peek() == Some('E') {
    self.i += 1
    if self.peek() == Some('+') || self.peek() == Some('-') { self.i += 1 }
    let exponent = self.i
    while self.peek() is Some(c) && digit(c) { self.i += 1 }
    if exponent == self.i { raise Syntax(self.i, "missing exponent digits") }
  }
  String::from_array(self.chars[start:self.i])
}

///|
fn lex(source : String, limits : Limits) -> Array[Token] raise QueryError {
  limits.validate()
  if source.length() > limits.max_query_chars { raise Resource("query characters") }
  let l = Lexer::{ chars: source.to_array(), i: 0 }
  let tokens = []
  while l.i < l.chars.length() {
    if tokens.length() >= limits.max_tokens { raise Resource("query tokens") }
    let c = l.chars[l.i]
    if space(c) { l.i += 1; continue }
    if c == '#' {
      while l.peek() is Some(c) && c != '\n' && c != '\r' { l.i += 1 }
      continue
    }
    let position = l.i
    let value = if c == '"' || c == '\'' {
      StringToken(l.quoted(c))
    } else if (c == '?' || c == '$') && l.peek(delta=1) is Some(n) && name_char(n) {
      l.i += 1
      let start = l.i
      while l.peek() is Some(n) && name_char(n) { l.i += 1 }
      Var(String::from_array(l.chars[start:l.i]))
    } else if digit(c) || (c == '.' && l.peek(delta=1) is Some(n) && digit(n)) {
      NumToken(l.number())
    } else if name_char(c) || c == ':' {
      let start = l.i
      l.i += 1
      while l.peek() is Some(n) && (name_char(n) || n == ':' || n == '-' ||
        (n == '.' && l.peek(delta=1) is Some(after) && name_char(after))) {
        l.i += 1
      }
      Word(String::from_array(l.chars[start:l.i]))
    } else {
      let mut end = l.i + 1
      if c == '<' {
        while end < l.chars.length() && !space(l.chars[end]) &&
          l.chars[end] != '>' && l.chars[end] != '<' { end += 1 }
      }
      if c == '<' && end < l.chars.length() && l.chars[end] == '>' {
        l.i += 1
        let text = StringBuilder::new()
        while l.i < end {
          let ch = l.chars[l.i]
          l.i += 1
          if ch == '\\' {
            let escape = l.peek()
            l.i += 1
            text.write_char(match escape {
              Some('u') => l.unicode(4)
              Some('U') => l.unicode(8)
              _ => raise Syntax(l.i, "IRI only permits Unicode escapes")
            })
          } else { text.write_char(ch) }
        }
        l.i += 1
        IriToken(text.to_string())
      } else {
        l.i += 1
        let mut op = c.to_string()
        match l.peek() {
          Some(n) => if (c == '!' || c == '<' || c == '>') && n == '=' ||
            (c == '&' && n == '&') || (c == '|' && n == '|') ||
            (c == '^' && n == '^') {
            op += n.to_string()
            l.i += 1
          }
          None => ()
        }
        if !"{}().;,*/+-=!<>|^?@[]&".contains(c.to_string()) {
          raise Syntax(position, "unexpected character")
        }
        Symbol(op)
      }
    }
    tokens.push({ value, position })
  }
  tokens.push({ value: EndToken, position: source.length() })
  tokens
}
