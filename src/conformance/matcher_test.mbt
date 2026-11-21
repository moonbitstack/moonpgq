// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The graph a case runs against, with the lookups the expected values are
/// written in: a vertex by its name, an edge by `out-label->in`, a vertex
/// property by `name-key->value`.
struct Fixture {
  store : @memory.Store
  vertices : Map[String, @pgq.Vertex]
  edges : Map[String, @pgq.Edge]
}

///|
fn Fixture::of(store : @memory.Store) -> Fixture {
  let vertices : Map[String, @pgq.Vertex] = Map([])
  let edges : Map[String, @pgq.Edge] = Map([])
  for vertex in store.vertices().to_array() {
    for name in vertex.values("name") {
      vertices[name.to_text()] = vertex
    }
  }
  for edge in store.edges().to_array() {
    let out_name = match edge.out_vertex() {
      Some(vertex) =>
        vertex.property("name").map(fn(value) { value.to_text() }).unwrap_or("")
      None => ""
    }
    let in_name = match edge.in_vertex() {
      Some(vertex) =>
        vertex.property("name").map(fn(value) { value.to_text() }).unwrap_or("")
      None => ""
    }
    let key = out_name + "-" + edge.label() + "->" + in_name
    edges[key] = edge
  }
  { store, vertices, edges, }
}

///|
/// Reads one cell of an expected-result table. The notation is the one the
/// feature files use: `v[marko]`, `e[marko-knows->vadas]`, `d[29].i`,
/// `l[1,2]`, `m[{...}]`, `p[a,b]`.
fn parse_cell(
  text : String,
  fixture : Fixture,
) -> @pgq.Value raise @pgq.Refused {
  let trimmed = text
  if trimmed == "null" {
    return @pgq.Value::Nil
  }
  if trimmed == "true" {
    return @pgq.Value::Bool(true)
  }
  if trimmed == "false" {
    return @pgq.Value::Bool(false)
  }
  if has_prefix(trimmed, "v[") {
    if has_suffix(trimmed, "].id") {
      let name = inside(trimmed, 2, 4)
      return vertex_named(fixture, name).id()
    }
    if has_suffix(trimmed, "].sid") {
      let name = inside(trimmed, 2, 5)
      return @pgq.Value::Text(vertex_named(fixture, name).id().to_text())
    }
    if has_suffix(trimmed, "]") {
      let name = inside(trimmed, 2, 1)
      return @pgq.Value::Vertex(vertex_named(fixture, name))
    }
  }
  if has_prefix(trimmed, "e[") {
    if has_suffix(trimmed, "].id") {
      let name = inside(trimmed, 2, 4)
      return edge_named(fixture, name).id()
    }
    if has_suffix(trimmed, "].sid") {
      let name = inside(trimmed, 2, 5)
      return @pgq.Value::Text(edge_named(fixture, name).id().to_text())
    }
    if has_suffix(trimmed, "]") {
      let name = inside(trimmed, 2, 1)
      return @pgq.Value::Edge(edge_named(fixture, name))
    }
  }
  if has_prefix(trimmed, "prop[") && has_suffix(trimmed, "]") {
    let body = inside(trimmed, 5, 1)
    match body.find(",") {
      Some(comma) =>
        return @pgq.Value::Property(
          @pgq.Property::new(
            body.exact_view(end=comma).to_owned(),
            parse_cell(body.exact_view(start=comma + 1).to_owned(), fixture),
          ),
        )
      None => ()
    }
  }
  if has_prefix(trimmed, "d[") && has_suffix(trimmed, "]") == false {
    match number_cell(trimmed) {
      Some(value) => return value
      None => ()
    }
  }
  if has_prefix(trimmed, "l[") && has_suffix(trimmed, "]") {
    return @pgq.Value::List(
      split_items(inside(trimmed, 2, 1)).map(fn(item) raise @pgq.Refused {
        parse_cell(item, fixture)
      }),
    )
  }
  if has_prefix(trimmed, "s[") && has_suffix(trimmed, "]") {
    return @pgq.Value::List(
      split_items(inside(trimmed, 2, 1)).map(fn(item) raise @pgq.Refused {
        parse_cell(item, fixture)
      }),
    )
  }
  if has_prefix(trimmed, "str[") && has_suffix(trimmed, "]") {
    return @pgq.Value::Text(inside(trimmed, 4, 1))
  }
  if has_prefix(trimmed, "m[") && has_suffix(trimmed, "]") {
    let body = inside(trimmed, 2, 1)
    let parsed = @json.parse(body) catch {
      _ => raise @pgq.Refused::Malformed(0, body, "a JSON object")
    }
    return json_to_value(parsed, fixture)
  }
  if has_prefix(trimmed, "p[") && has_suffix(trimmed, "]") {
    let body = inside(trimmed, 2, 1)
    return @pgq.Value::Path(
      @pgq.Path::new(
        split_items(body).map(fn(item) raise @pgq.Refused {
          parse_cell(item, fixture)
        }),
      ),
    )
  }
  @pgq.Value::Text(trimmed)
}

///|
fn has_prefix(text : String, prefix : String) -> Bool {
  text.has_prefix(prefix)
}

///|
fn has_suffix(text : String, suffix : String) -> Bool {
  text.has_suffix(suffix)
}

///|
/// The body of a bracketed cell, dropping the opening and closing brackets.
fn inside(text : String, open : Int32, close : Int32) -> String {
  text.exact_view(start=open, end=text.length() - close).to_owned()
}

///|
fn split_items(body : String) -> Array[String] {
  let items : Array[String] = []
  if body.length() == 0 {
    return items
  }
  let mut depth = 0
  let mut start = 0
  for index in 0..<body.length() {
    let ch = body.get_char(index).unwrap_or(' ')
    if ch == '[' || ch == '{' {
      depth = depth + 1
    } else if ch == ']' || ch == '}' {
      depth = depth - 1
    } else if ch == ',' && depth == 0 {
      items.push(body.exact_view(start~, end=index).trim().to_owned())
      start = index + 1
    }
  }
  items.push(body.exact_view(start~).trim().to_owned())
  items
}

///|
fn vertex_named(
  fixture : Fixture,
  name : String,
) -> @pgq.Vertex raise @pgq.Refused {
  match fixture.vertices.get(name) {
    Some(vertex) => vertex
    None => raise @pgq.Refused::Malformed(0, name, "a vertex of this graph")
  }
}

///|
fn edge_named(fixture : Fixture, name : String) -> @pgq.Edge raise @pgq.Refused {
  match fixture.edges.get(name) {
    Some(edge) => edge
    None => raise @pgq.Refused::Malformed(0, name, "an edge of this graph")
  }
}

///|
/// A typed number cell: `d[29].i` is the integer 29, `d[1.0].d` the double.
fn number_cell(text : String) -> @pgq.Value? {
  if !has_prefix(text, "d[") {
    return None
  }
  let dot = text.rev_find("]")
  let close = match dot {
    Some(index) => index
    None => return None
  }
  let body = text.exact_view(start=2, end=close).to_owned()
  let suffix = text.exact_view(start=close + 1).to_owned()
  if body == "NaN" {
    return Some(@pgq.Value::Double(@double.not_a_number))
  }
  if body == "Infinity" {
    return Some(@pgq.Value::Double(@double.infinity))
  }
  if body == "-Infinity" {
    return Some(@pgq.Value::Double(@double.neg_infinity))
  }
  let is_double = suffix.contains("d") ||
    suffix.contains("f") ||
    body.contains(".")
  if is_double {
    Some(@pgq.Value::Double(parse_number(body)))
  } else {
    Some(@pgq.Value::Int(parse_number(body).to_int64()))
  }
}

///|
fn parse_number(text : String) -> Double {
  let mut negative = false
  let mut total = 0.0
  let mut scale = 1.0
  let mut after_point = false
  for index in 0..<text.length() {
    let ch = text.get_char(index).unwrap_or(' ')
    if ch == '-' && index == 0 {
      negative = true
    } else if ch == '.' {
      after_point = true
    } else if ch >= '0' && ch <= '9' {
      let digit = ch.to_int().to_double() - '0'.to_int().to_double()
      if after_point {
        scale = scale / 10.0
        total = total + digit * scale
      } else {
        total = total * 10.0 + digit
      }
    }
  }
  if negative {
    -total
  } else {
    total
  }
}

///|
/// A map cell keeps its values as text, so each one is read back as a cell.
fn json_to_value(
  json : @json.Json,
  fixture : Fixture,
) -> @pgq.Value raise @pgq.Refused {
  match json {
    Null => @pgq.Value::Nil
    True => @pgq.Value::Bool(true)
    False => @pgq.Value::Bool(false)
    Number(number, ..) =>
      if number == number.to_int().to_double() {
        @pgq.Value::Int(number.to_int64())
      } else {
        @pgq.Value::Double(number)
      }
    String(text) =>
      if looks_like_cell(text) {
        parse_cell(text, fixture)
      } else {
        @pgq.Value::Text(text)
      }
    Array(items) =>
      @pgq.Value::List(
        items.map(fn(item) raise @pgq.Refused { json_to_value(item, fixture) }),
      )
    Object(fields) => {
      let entries : Array[(@pgq.Value, @pgq.Value)] = []
      for field in fields {
        entries.push(
          (
            @pgq.Value::Text(token_key(field.0)),
            json_to_value(field.1, fixture),
          ),
        )
      }
      @pgq.Value::Dict(entries)
    }
  }
}

///|
/// A map key that names an element token is written `t[id]` in the expected
/// tables; the engine's maps carry the token's name.
fn token_key(key : String) -> String {
  if key == "t[id]" || key == "t[label]" || key == "t[key]" || key == "t[value]" {
    key.exact_view(start=2, end=key.length() - 1).to_owned()
  } else {
    key
  }
}

///|
fn looks_like_cell(text : String) -> Bool {
  text.has_prefix("v[") ||
  text.has_prefix("e[") ||
  text.has_prefix("d[") ||
  text.has_prefix("l[") ||
  text.has_prefix("s[") ||
  text.has_prefix("m[") ||
  text.has_prefix("p[") ||
  text.has_prefix("prop[")
}

///|
/// Equality as the feature files mean it: an integer is not a double, and two
/// numbers of the same type compare by value.
fn same(actual : @pgq.Value, expected : @pgq.Value) -> Bool {
  match (actual, expected) {
    (Nil, Nil) => true
    (Bool(a), Bool(b)) => a == b
    (Int(a), Int(b)) => a == b
    (Double(a), Double(b)) => a == b || (a.is_nan() && b.is_nan())
    (Text(a), Text(b)) => a == b
    (List(a), List(b)) => {
      guard a.length() == b.length() else { return false }
      for index in 0..<a.length() {
        guard same(a[index], b[index]) else { return false }
      }
      true
    }
    (Dict(a), Dict(b)) => {
      guard a.length() == b.length() else { return false }
      for entry in a {
        match array_find(b, fn(other) { same(other.0, entry.0) }) {
          Some(other) => if !same(entry.1, other.1) { return false }
          None => return false
        }
      }
      true
    }
    (Entry(a, b), Entry(c, d)) => same(a, c) && same(b, d)
    (Path(a), Path(b)) => {
      guard a.size() == b.size() else { return false }
      for index in 0..<a.size() {
        guard same(a.objects()[index], b.objects()[index]) else { return false }
      }
      true
    }
    (Vertex(a), Vertex(b)) => a.id().equals(b.id())
    (Edge(a), Edge(b)) => a.id().equals(b.id())
    (Property(a), Property(b)) =>
      a.key() == b.key() && same(a.value(), b.value())
    _ => false
  }
}

///|
fn[T] array_find(items : Array[T], accept : (T) -> Bool) -> T? {
  for item in items {
    if accept(item) {
      return Some(item)
    }
  }
  None
}
