// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Everything a traversal carries: property values, element ids and results.
///
/// A traversal is untyped, so one value type covers numbers, text, collections
/// and graph elements rather than making every step generic over the result
/// type the way a host-language library can.
pub(all) enum Value {
  /// Absent: a missing property, or a result that is null by definition.
  Nil
  Bool(Bool)
  Int(Int64)
  Double(Double)
  Text(String)
  List(Array[Value])
  /// Keys keep their insertion order, and may themselves be any value.
  Dict(Array[(Value, Value)])
  /// One key and its value: what `unfold()` of a map produces, and what
  /// `select(keys)` and `select(values)` read.
  Entry(Value, Value)
  Vertex(Vertex)
  Edge(Edge)
  Path(Path)
  Property(Property)
}

///|
pub fn Value::of_int(n : Int64) -> Value {
  Value::Int(n)
}

///|
pub fn Value::of_text(text : StringView) -> Value {
  Value::Text(text.to_owned())
}

///|
/// The position of a value's type in the total order that orders results
/// across types: nulls first, then booleans, numbers, text, collections and
/// elements. Ordering is only defined within a type by the language, so the
/// cross-type order is ours to pick; this one matches what a table of results
/// reads like.
pub fn Value::rank(self : Value) -> Int32 {
  match self {
    Nil => 0
    Bool(_) => 1
    Int(_) | Double(_) => 2
    Text(_) => 3
    List(_) => 4
    Dict(_) => 5
    Entry(_, _) => 5
    Vertex(_) => 6
    Edge(_) => 7
    Path(_) => 8
    Property(_) => 9
  }
}

///|
pub fn Value::is_number(self : Value) -> Bool {
  match self {
    Int(_) | Double(_) => true
    _ => false
  }
}

///|
/// The value as a floating point number. Text is not converted: a query that
/// compares text with a number is a mistake, not a coercion.
pub fn Value::as_double(self : Value) -> Double? {
  match self {
    Int(n) => Some(n.to_double())
    Double(d) => Some(d)
    _ => None
  }
}

///|
pub fn Value::equals(self : Value, other : Value) -> Bool {
  match (self, other) {
    (Nil, Nil) => true
    (Bool(a), Bool(b)) => a == b
    (Int(a), Int(b)) => a == b
    (Int(a), Double(b)) | (Double(b), Int(a)) => a.to_double() == b
    (Double(a), Double(b)) => a == b || (a.is_nan() && b.is_nan())
    (Text(a), Text(b)) => a == b
    (List(a), List(b)) => {
      guard a.length() == b.length() else { return false }
      for i in 0..<a.length() {
        guard a[i].equals(b[i]) else { return false }
      }
      true
    }
    (Dict(a), Dict(b)) => {
      guard a.length() == b.length() else { return false }
      for entry in a {
        guard b.any(fn(other) {
          other.0.equals(entry.0) && other.1.equals(entry.1)
        }) else {
          return false
        }
      }
      true
    }
    (Entry(a, b), Entry(c, d)) => a.equals(c) && b.equals(d)
    (Vertex(a), Vertex(b)) => a.equals(b)
    (Edge(a), Edge(b)) => a.equals(b)
    (Path(a), Path(b)) => {
      guard a.size() == b.size() else { return false }
      for i in 0..<a.size() {
        guard a.objects()[i].equals(b.objects()[i]) else { return false }
      }
      true
    }
    (Property(a), Property(b)) =>
      a.key() == b.key() && a.value().equals(b.value())
    _ => false
  }
}

///|
pub fn Value::compare(self : Value, other : Value) -> Int32 {
  let left = self.rank()
  let right = other.rank()
  if left != right {
    return if left < right { -1 } else { 1 }
  }
  match (self, other) {
    (Nil, Nil) => 0
    (Bool(a), Bool(b)) => if a == b { 0 } else if a { 1 } else { -1 }
    (Int(a), Int(b)) => a.compare(b)
    (Double(a), Double(b)) => a.compare(b)
    (Int(a), Double(b)) => a.to_double().compare(b)
    (Double(a), Int(b)) => a.compare(b.to_double())
    (Text(a), Text(b)) => compare_text(a, b)
    (List(a), List(b)) => compare_sequences(a, b)
    (Dict(a), Dict(b)) => compare_entries(a, b)
    (Entry(a, b), Entry(c, d)) => {
      let by_key = a.compare(c)
      if by_key != 0 {
        by_key
      } else {
        b.compare(d)
      }
    }
    (Vertex(a), Vertex(b)) => a.key().compare(b.key())
    (Edge(a), Edge(b)) => a.key().compare(b.key())
    (Path(a), Path(b)) => compare_sequences(a.objects(), b.objects())
    (Property(a), Property(b)) => {
      let by_key = a.key().compare(b.key())
      if by_key != 0 {
        by_key
      } else {
        a.value().compare(b.value())
      }
    }
    _ => 0
  }
}

///|
/// Text compares character by character, as a dictionary does. The order the
/// core library gives strings is by length first, which would put `lop` before
/// `josh` and make an ordered result differ from every other implementation.
pub fn compare_text(left : String, right : String) -> Int32 {
  let common = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index in 0..<common {
    let a = left.get_char(index).unwrap_or('\u{0}')
    let b = right.get_char(index).unwrap_or('\u{0}')
    if a != b {
      return if a < b { -1 } else { 1 }
    }
  }
  left.length().compare(right.length())
}

///|
fn compare_sequences(left : Array[Value], right : Array[Value]) -> Int32 {
  let common = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for i in 0..<common {
    let order = left[i].compare(right[i])
    if order != 0 {
      return order
    }
  }
  left.length().compare(right.length())
}

///|
fn compare_entries(
  left : Array[(Value, Value)],
  right : Array[(Value, Value)],
) -> Int32 {
  let common = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for i in 0..<common {
    let by_key = left[i].0.compare(right[i].0)
    if by_key != 0 {
      return by_key
    }
    let by_value = left[i].1.compare(right[i].1)
    if by_value != 0 {
      return by_value
    }
  }
  left.length().compare(right.length())
}

///|
pub impl Eq for Value with fn equal(self, other) {
  self.equals(other)
}

///|
pub impl Compare for Value with fn compare(self, other) {
  Value::compare(self, other)
}

///|
/// The value as text, in the notation the graph formats use: elements as
/// `v[id]` and `e[id]`, paths as `path[...]`, properties as `p[key->value]`.
pub fn Value::to_text(self : Value) -> String {
  match self {
    Nil => "null"
    Bool(true) => "true"
    Bool(false) => "false"
    Int(n) => n.to_string()
    Double(d) => format_double(d)
    Text(text) => text
    List(items) => "[" + items.map(fn(item) { item.to_text() }).join(", ") + "]"
    Dict(entries) =>
      "{" +
      entries
      .map(fn(entry) { entry.0.to_text() + "=" + entry.1.to_text() })
      .join(", ") +
      "}"
    Entry(key, value) => key.to_text() + "=" + value.to_text()
    Vertex(vertex) => vertex.to_text()
    Edge(edge) => edge.to_text()
    Path(path) => path.to_text()
    Property(property) => property.to_text()
  }
}

///|
pub impl Show for Value with fn to_string(self) {
  self.to_text()
}

///|
/// A double as the number formats print it: an integral value keeps its `.0`
/// so that `1.0` does not read back as the integer `1`.
pub fn format_double(value : Double) -> String {
  if value.is_nan() {
    return "NaN"
  }
  if value == @double.infinity {
    return "Infinity"
  }
  if value == @double.neg_infinity {
    return "-Infinity"
  }
  let text = value.to_string()
  let needs_point = !text.contains(".") &&
    !text.contains("e") &&
    !text.contains("E")
  if needs_point {
    text + ".0"
  } else {
    text
  }
}

///|
/// A stable key for a value, used where a step has to remember which values it
/// has already seen. Elements compare by graph and id, so two traversers that
/// reached the same vertex are the same key.
pub fn Value::key(self : Value) -> String {
  match self {
    Vertex(vertex) =>
      "v:" + vertex.graph.uid().to_string() + ":" + vertex.id().to_text()
    Edge(edge) =>
      "e:" + edge.graph.uid().to_string() + ":" + edge.id().to_text()
    _ => "x:" + self.to_text()
  }
}
