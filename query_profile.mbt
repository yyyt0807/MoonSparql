///|
/// Static query structure for editors, local source catalogues and capability
/// checks. Counts describe syntax, independently of data and result cardinality.
pub struct QueryProfile {
  priv form : String
  priv variables : Array[String]
  priv sources : Array[(Term, Bool)]
  priv mut subqueries : Int32
  priv mut existence_checks : Int32
  priv mut property_paths : Int32
  priv mut aggregates : Int32
}

///|
/// Pairs contain an IRI and whether its clause is FROM NAMED.
pub fn PreparedQuery::dataset_sources(
  self : PreparedQuery,
) -> Array[(Term, Bool)] {
  self.query.datasets.copy()
}

///|
fn QueryProfile::expression(self : QueryProfile, e : Expr) -> Unit {
  match e {
    Unary(_, item) => self.expression(item)
    Binary(_, left, right) => {
      self.expression(left)
      self.expression(right)
    }
    Call(_, args) =>
      for item in args {
        self.expression(item)
      }
    Aggregate(_, value, _, _) => {
      self.aggregates += 1
      if value is Some(item) {
        self.expression(item)
      }
    }
    Exists(group, _) => {
      self.existence_checks += 1
      self.group(group)
    }
    _ => ()
  }
}

///|
fn QueryProfile::group(self : QueryProfile, group : Group) -> Unit {
  for pattern in group.patterns {
    match pattern {
      Triple(_, Predicate(_) | PathVar(_), _) => ()
      Triple(_, _, _) => self.property_paths += 1
      Filter(e) | Bind(e, _) => self.expression(e)
      Nested(g) | Optional(g) | Graph(_, g) | Minus(g) => self.group(g)
      Union(groups) =>
        for g in groups {
          self.group(g)
        }
      Subselect(q) => {
        self.subqueries += 1
        self.query(q)
      }
      Values(_, _) => ()
    }
  }
}

///|
fn QueryProfile::query(self : QueryProfile, q : Query) -> Unit {
  self.group(q.group)
  for p in q.projections {
    self.expression(p.expression)
  }
  for (e, _) in q.group_by {
    self.expression(e)
  }
  for e in q.having {
    self.expression(e)
  }
  for (e, _) in q.order {
    self.expression(e)
  }
}

///|
pub fn PreparedQuery::profile(self : PreparedQuery) -> QueryProfile {
  let result = QueryProfile::{
    form: self.form(),
    variables: solution_variables(self.query),
    sources: self.dataset_sources(),
    subqueries: 0,
    existence_checks: 0,
    property_paths: 0,
    aggregates: 0,
  }
  result.query(self.query)
  result
}

///|
pub fn QueryProfile::to_json(self : QueryProfile) -> String {
  Json::object({
    "version": Json::number(1.0),
    "form": Json::string(self.form),
    "variables": Json::array(self.variables.map(Json::string)),
    "datasetSources": Json::array(
      self.sources.map(entry => {
        Json::object({
          "iri": Json::string(entry.0.lexical),
          "named": Json::boolean(entry.1),
        })
      }),
    ),
    "subqueries": Json::number(self.subqueries.to_double()),
    "existenceChecks": Json::number(self.existence_checks.to_double()),
    "propertyPaths": Json::number(self.property_paths.to_double()),
    "aggregates": Json::number(self.aggregates.to_double()),
  }).stringify()
}
