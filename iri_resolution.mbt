///|
priv struct IriReference {
  scheme : String?
  authority : String?
  path : String
  query : String?
  fragment : String?
}

///|
fn split_component(text : String, separator : String) -> (String, String?) {
  match text.split_once(separator) {
    Some((left, right)) => (left.to_owned(), Some(right.to_owned()))
    None => (text, None)
  }
}

///|
fn scheme_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn valid_scheme(text : String) -> Bool {
  let chars = text.to_array()
  !chars.is_empty() &&
  scheme_letter(chars[0]) &&
  chars.all(c => {
    scheme_letter(c) || digit(c) || c == '+' || c == '-' || c == '.'
  })
}

///|
fn IriReference::parse(value : String) -> IriReference {
  let (main, fragment) = split_component(value, "#")
  let (main, query) = split_component(main, "?")
  let (candidate, rest) = split_component(main, ":")
  let (scheme, body) = if rest is Some(tail) && valid_scheme(candidate) {
    (Some(candidate), tail)
  } else {
    (None, main)
  }
  let (authority, path) = if body.has_prefix("//") {
    let (host, path) = split_component(body[2:].to_owned(), "/")
    (
      Some(host),
      match path {
        Some(tail) => "/" + tail
        None => ""
      },
    )
  } else {
    (None, body)
  }
  { scheme, authority, path, query, fragment, }
}

///|
fn remove_dot_segments(path : String) -> String {
  let parts = path.split("/").to_array()
  let result = []
  let rooted = path.has_prefix("/")
  for i, part in parts {
    let segment = part.to_owned()
    if segment == ".." {
      if result.length() > (if rooted { 1 } else { 0 }) {
        ignore(result.pop())
      }
    } else if segment != "." {
      result.push(segment)
      continue
    }
    if i == parts.length() - 1 {
      result.push("")
    }
  }
  result.join("/")
}

///|
fn parent_path(path : String) -> String {
  let mut end = path.length()
  while end > 0 && path[end - 1] != '/' {
    end -= 1
  }
  path[:end].to_owned()
}

///|
fn resolve_query_iri(value : String, base : String?) -> String raise QueryError {
  let reference = IriReference::parse(value)
  if reference.scheme is Some(_) {
    check_iri(value)
    return value
  }
  guard base is Some(base) else {
    raise Unsupported(0, "relative IRI requires BASE or an explicit base URI")
  }
  let origin = IriReference::parse(base)
  guard origin.scheme is Some(scheme) else {
    raise InvalidInput("query base must have an absolute IRI scheme")
  }
  let authority = match reference.authority {
    Some(host) => Some(host)
    None => origin.authority
  }
  let (path, query) = if reference.authority is Some(_) ||
    reference.path.has_prefix("/") {
    (remove_dot_segments(reference.path), reference.query)
  } else if reference.path.is_empty() {
    (
      origin.path,
      match reference.query {
        Some(q) => Some(q)
        None => origin.query
      },
    )
  } else {
    let prefix = if origin.authority is Some(_) && origin.path.is_empty() {
      "/"
    } else {
      parent_path(origin.path)
    }
    (remove_dot_segments(prefix + reference.path), reference.query)
  }
  let result = StringBuilder()
  result.write_string(scheme + ":")
  if authority is Some(host) {
    result.write_string("//" + host)
  }
  result.write_string(path)
  if query is Some(q) {
    result.write_string("?" + q)
  }
  if reference.fragment is Some(fragment) {
    result.write_string("#" + fragment)
  }
  let resolved = result.to_string()
  check_iri(resolved)
  resolved
}
