///|
fn binary_precedence(value : Lexeme) -> Int32 {
  match value {
    Symbol("||") => 1
    Symbol("&&") => 2
    Symbol("=" | "!=" | "<" | ">" | "<=" | ">=") => 3
    Symbol("+" | "-") => 4
    Symbol("*" | "/") => 5
    _ => -1
  }
}

///|
fn aggregate_name(name : String) -> Bool {
  ["COUNT", "SUM", "AVG", "MIN", "MAX", "SAMPLE", "GROUP_CONCAT"].contains(name)
}

///|
fn supported_function(name : String) -> Bool {
  extended_string_function(name) ||
  date_time_function(name) ||
  [
    "BOUND", "STR", "LANG", "DATATYPE", "ISIRI", "ISURI", "ISBLANK", "ISLITERAL",
    "ISNUMERIC", "SAMETERM", "STRLEN", "CONTAINS", "STRSTARTS", "STRENDS", "LCASE",
    "UCASE", "CONCAT", "COALESCE", "IF", "LANGMATCHES", "ABS", "CEIL", "FLOOR", "ROUND",
    "STRDT", "STRLANG", "IRI", "URI",
  ].contains(name)
}

///|
fn Parser::function_call(self : Parser, name : String) -> Expr raise QueryError {
  if !aggregate_name(name) && !supported_function(name) && !numeric_cast(name) {
    raise Unsupported(self.position(), "function " + name)
  }
  self.expect("(")
  if aggregate_name(name) {
    let distinct = self.word("DISTINCT")
    let value = if name == "COUNT" && self.sym("*") {
      None
    } else {
      Some(self.expression())
    }
    let separator = if name == "GROUP_CONCAT" && self.sym(";") {
      self.require_word("SEPARATOR")
      self.expect("=")
      match self.advance() {
        StringToken(text) => text
        _ =>
          raise Syntax(
            self.position(),
            "expected GROUP_CONCAT separator string",
          )
      }
    } else {
      " "
    }
    self.expect(")")
    Aggregate(name, value, distinct, separator)
  } else {
    let arguments = []
    if !self.sym(")") {
      arguments.push(self.expression())
      while self.sym(",") {
        arguments.push(self.expression())
      }
      self.expect(")")
    }
    Call(name, arguments)
  }
}

///|
fn Parser::primary(self : Parser) -> Expr raise QueryError {
  if self.word("EXISTS") {
    Exists(self.group(), false)
  } else if self.word("NOT") {
    self.require_word("EXISTS")
    Exists(self.group(), true)
  } else if self.sym("(") {
    let expression = self.expression()
    self.expect(")")
    expression
  } else if self.sym("!") {
    Unary("!", self.expression(min_precedence=6))
  } else if self.sym("+") {
    Unary("+", self.expression(min_precedence=6))
  } else if self.sym("-") {
    Unary("-", self.expression(min_precedence=6))
  } else {
    match self.current() {
      Var(_) => Reference(self.variable())
      Word(_) | IriToken(_) if self.tokens.get(self.i + 1)
        is Some({ value: Symbol("("), .. }) => {
        let name = match self.current() {
          Word(word) if !word.contains(":") => {
            ignore(self.advance())
            word.to_upper()
          }
          _ => self.read_term().lexical
        }
        self.function_call(name)
      }
      _ => Constant(self.read_term())
    }
  }
}

///|
fn Parser::expression(
  self : Parser,
  min_precedence~ : Int32 = 0,
) -> Expr raise QueryError {
  self.enter()
  let mut left = self.primary()
  while true {
    if min_precedence <= 3 {
      let negative = self.word("NOT")
      if negative || self.word("IN") {
        if negative {
          self.require_word("IN")
        }
        self.expect("(")
        let args = [left]
        if !self.sym(")") {
          args.push(self.expression())
          while self.sym(",") {
            args.push(self.expression())
          }
          self.expect(")")
        }
        left = if negative {
          Unary("!", Call("IN", args))
        } else {
          Call("IN", args)
        }
        continue
      }
    }
    let precedence = binary_precedence(self.current())
    if precedence < min_precedence {
      break
    }
    let op = match self.advance() {
      Symbol(op) => op
      _ => raise Syntax(self.position(), "expected expression operator")
    }
    left = Binary(op, left, self.expression(min_precedence=precedence + 1))
  }
  self.depth -= 1
  left
}
