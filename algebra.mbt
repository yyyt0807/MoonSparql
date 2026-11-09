///|
priv enum Slot {
  Fixed(Term)
  Variable(String)
}

///|
priv enum Path {
  Predicate(Term)
  PathVar(String)
  Inverse(Path)
  Sequence(Path, Path)
  Alternative(Path, Path)
  Negated(Array[Term], Array[Term])
  ZeroMore(Path)
  OneMore(Path)
  ZeroOne(Path)
}

///|
priv enum Expr {
  Constant(Term)
  Reference(String)
  Unary(String, Expr)
  Binary(String, Expr, Expr)
  Call(String, Array[Expr])
  Aggregate(String, Expr?, Bool, String)
  Exists(Group, Bool)
}

///|
priv enum Pattern {
  Triple(Slot, Path, Slot)
  Optional(Group)
  Union(Array[Group])
  Nested(Group)
  Filter(Expr)
  Bind(Expr, String)
  Values(Array[String], Array[Array[Term?]])
  Graph(Slot, Group)
  Minus(Group)
  Subselect(Query)
}

///|
priv struct Group {
  patterns : Array[Pattern]
}

///|
priv enum QueryForm {
  Select
  Ask
  Construct
} derive(Eq)

///|
priv struct Projection {
  expression : Expr
  variable : String
}

///|
priv struct Query {
  form : QueryForm
  projections : Array[Projection]
  all : Bool
  distinct : Bool
  base_uri : String?
  group : Group
  group_by : Array[(Expr, String?)]
  datasets : Array[(Term, Bool)]
  trailing : Group
  having : Array[Expr]
  order : Array[(Expr, Bool)]
  offset : Int32
  limit : Int32?
  template : Array[(Slot, Path, Slot)]
}

///|
pub struct Binding {
  priv values : Map[String, Term]
}

///|
fn Binding::empty() -> Binding {
  { values: Map([]), }
}

///|
fn Binding::copy(self : Binding) -> Binding {
  { values: self.values.copy(), }
}

///|
pub fn Binding::get(self : Binding, variable : String) -> Term? {
  self.values.get(variable)
}

///|
pub fn Binding::variables(self : Binding) -> Array[String] {
  let names = self.values.keys().to_array()
  names.sort()
  names
}

///|
pub fn Binding::length(self : Binding) -> Int32 {
  self.values.length()
}

///|
fn Binding::key(self : Binding, variables : Array[String]) -> String {
  let out = StringBuilder()
  for name in variables {
    match self.values.get(name) {
      Some(t) => out.write_string("B" + key_part(t.key()))
      None => out.write_string("U")
    }
  }
  out.to_string()
}

///|
fn Binding::bind(self : Binding, slot : Slot, value : Term) -> Bool {
  match slot {
    Fixed(t) => t == value
    Variable(name) =>
      match self.values.get(name) {
        Some(t) => t == value
        None => {
          self.values[name] = value
          true
        }
      }
  }
}

///|
fn Binding::resolve(self : Binding, slot : Slot) -> Term? {
  match slot {
    Fixed(t) => Some(t)
    Variable(name) => self.get(name)
  }
}

///|
fn Binding::merge(self : Binding, other : Binding) -> Binding? {
  let result = self.copy()
  for name, value in other.values {
    if !result.bind(Variable(name), value) {
      return None
    }
  }
  Some(result)
}
