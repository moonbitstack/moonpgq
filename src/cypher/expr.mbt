// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A row of bindings: a variable name and its value, in the order the query
/// bound them.
pub(all) struct Row {
  bindings : Array[(String, @pgq.Value)]
}

///|
pub fn Row::new() -> Row {
  { bindings: [], }
}

///|
pub fn Row::bindings(self : Row) -> Array[(String, @pgq.Value)] {
  self.bindings
}

///|
/// One query run against one graph, with the parameters it may refer to.
pub struct Session {
  graph : &@pgq.Graph
  parameters : Array[(String, @pgq.Value)]
}

///|
fn Row::get(self : Row, name : String) -> @pgq.Value? {
  for entry in self.bindings {
    if entry.0 == name {
      return Some(entry.1)
    }
  }
  None
}

///|
fn Row::has(self : Row, name : String) -> Bool {
  self.get(name) is Some(_)
}

///|
/// Binds a variable, replacing an earlier binding of the same name.
fn Row::put(self : Row, name : String, value : @pgq.Value) -> Row {
  let out : Array[(String, @pgq.Value)] = []
  let mut replaced = false
  for entry in self.bindings {
    if entry.0 == name {
      out.push((name, value))
      replaced = true
    } else {
      out.push(entry)
    }
  }
  if !replaced {
    out.push((name, value))
  }
  { bindings: out, }
}

///|
/// The truth of a value in a filter position: only `true` passes, and null is
/// "unknown", which also does not pass.
fn is_true(value : @pgq.Value) -> Bool {
  match value {
    Bool(flag) => flag
    _ => false
  }
}

///|
fn number_of(value : @pgq.Value) -> Double? {
  match value {
    Int(number) => Some(number.to_double())
    Double(number) => Some(number)
    _ => None
  }
}

///|
/// Text of a value as Cypher prints it inside a string function.
fn text_of(value : @pgq.Value) -> String {
  value.to_text()
}

///|
/// Reads a property of an entity, a field of a map, or an entry of a list.
fn read_property(target : @pgq.Value, key : String) -> @pgq.Value {
  match target {
    @pgq.Value::Vertex(vertex) =>
      vertex.property(key).unwrap_or(@pgq.Value::Nil)
    @pgq.Value::Edge(edge) => edge.property(key).unwrap_or(@pgq.Value::Nil)
    @pgq.Value::Dict(entries) =>
      match array_find(entries, fn(entry) { entry.0.to_text() == key }) {
        Some(entry) => entry.1
        None => @pgq.Value::Nil
      }
    _ => @pgq.Value::Nil
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

///|
/// Evaluates an expression in one row.
fn Session::eval(self : Session, row : Row, expr : Expr) -> @pgq.Value {
  match expr {
    Literal(value) => value
    Variable(name) => row.get(name).unwrap_or(@pgq.Value::Nil)
    Parameter(name) =>
      array_find(self.parameters, fn(entry) { entry.0 == name })
      .map(fn(entry) { entry.1 })
      .unwrap_or(@pgq.Value::Nil)
    Property(target, key) => read_property(self.eval(row, target), key)
    Index(target, index) => {
      let container = self.eval(row, target)
      match self.eval(row, index) {
        @pgq.Value::Text(key) => read_property(container, key)
        @pgq.Value::Int(position) =>
          match container {
            @pgq.Value::List(items) =>
              if position >= 0L && position < items.length().to_int64() {
                items[position.to_int()]
              } else {
                @pgq.Value::Nil
              }
            _ => @pgq.Value::Nil
          }
        _ => @pgq.Value::Nil
      }
    }
    ListLiteral(items) =>
      @pgq.Value::List(items.map(fn(item) { self.eval(row, item) }))
    MapLiteral(entries) =>
      @pgq.Value::Dict(
        entries.map(fn(entry) {
          (@pgq.Value::Text(entry.0), self.eval(row, entry.1))
        }),
      )
    Unary("NOT", operand) =>
      match self.eval(row, operand) {
        @pgq.Value::Bool(flag) => @pgq.Value::Bool(!flag)
        _ => @pgq.Value::Nil
      }
    Unary(_, operand) => {
      let value = self.eval(row, operand)
      match value {
        @pgq.Value::Int(number) => @pgq.Value::Int(-number)
        @pgq.Value::Double(number) => @pgq.Value::Double(-number)
        _ => @pgq.Value::Nil
      }
    }
    Binary("AND", left, right) =>
      match (self.eval(row, left), self.eval(row, right)) {
        (@pgq.Value::Bool(false), _) | (_, @pgq.Value::Bool(false)) =>
          @pgq.Value::Bool(false)
        (@pgq.Value::Bool(true), @pgq.Value::Bool(true)) =>
          @pgq.Value::Bool(true)
        _ => @pgq.Value::Nil
      }
    Binary("OR", left, right) =>
      match (self.eval(row, left), self.eval(row, right)) {
        (@pgq.Value::Bool(true), _) | (_, @pgq.Value::Bool(true)) =>
          @pgq.Value::Bool(true)
        (@pgq.Value::Bool(false), @pgq.Value::Bool(false)) =>
          @pgq.Value::Bool(false)
        _ => @pgq.Value::Nil
      }
    Binary("XOR", left, right) =>
      match (self.eval(row, left), self.eval(row, right)) {
        (@pgq.Value::Bool(a), @pgq.Value::Bool(b)) => @pgq.Value::Bool(a != b)
        _ => @pgq.Value::Nil
      }
    Binary(operator, left, right) =>
      self.binary(operator, self.eval(row, left), self.eval(row, right))
    IsNull(operand, negated) => {
      let is_null = self.eval(row, operand) is @pgq.Value::Nil
      @pgq.Value::Bool(if negated { !is_null } else { is_null })
    }
    Call(name, args, _) => self.call(row, name, args)
    Case(branches, fallback) => {
      for branch in branches {
        if is_true(self.eval(row, branch.0)) {
          return self.eval(row, branch.1)
        }
      }
      match fallback {
        Some(value) => self.eval(row, value)
        None => @pgq.Value::Nil
      }
    }
    Star => @pgq.Value::Nil
  }
}

///|
fn Session::binary(
  _self : Session,
  operator : String,
  left : @pgq.Value,
  right : @pgq.Value,
) -> @pgq.Value {
  match operator {
    "=" => @pgq.Value::Bool(left.equals(right))
    "<>" => @pgq.Value::Bool(!left.equals(right))
    "<" => @pgq.Value::Bool(compare_ordered(left, right) < 0)
    "<=" => @pgq.Value::Bool(compare_ordered(left, right) <= 0)
    ">" => @pgq.Value::Bool(compare_ordered(left, right) > 0)
    ">=" => @pgq.Value::Bool(compare_ordered(left, right) >= 0)
    "IN" =>
      match right {
        @pgq.Value::List(items) =>
          @pgq.Value::Bool(items.any(fn(item) { item.equals(left) }))
        _ => @pgq.Value::Nil
      }
    "STARTS WITH" =>
      match (left, right) {
        (@pgq.Value::Text(text), @pgq.Value::Text(prefix)) =>
          @pgq.Value::Bool(text.has_prefix(prefix))
        _ => @pgq.Value::Nil
      }
    "ENDS WITH" =>
      match (left, right) {
        (@pgq.Value::Text(text), @pgq.Value::Text(suffix)) =>
          @pgq.Value::Bool(text.has_suffix(suffix))
        _ => @pgq.Value::Nil
      }
    "CONTAINS" =>
      match (left, right) {
        (@pgq.Value::Text(text), @pgq.Value::Text(part)) =>
          @pgq.Value::Bool(text.contains(part))
        _ => @pgq.Value::Nil
      }
    "=~" => @pgq.Value::Nil
    "+" =>
      match (left, right) {
        (@pgq.Value::Text(a), @pgq.Value::Text(b)) => @pgq.Value::Text(a + b)
        (@pgq.Value::Text(a), _) => @pgq.Value::Text(a + text_of(right))
        (@pgq.Value::List(a), @pgq.Value::List(b)) => @pgq.Value::List(a + b)
        _ => arith(left, right, "+")
      }
    _ => arith(left, right, operator)
  }
}

///|
/// Compares two values for the ordering operators, with numbers compared as
/// numbers and everything else by the value order this module defines.
fn compare_ordered(left : @pgq.Value, right : @pgq.Value) -> Int32 {
  match (left, right) {
    (@pgq.Value::Int(a), @pgq.Value::Double(b)) => a.to_double().compare(b)
    (@pgq.Value::Double(a), @pgq.Value::Int(b)) => a.compare(b.to_double())
    _ => left.compare(right)
  }
}

///|
fn arith(
  left : @pgq.Value,
  right : @pgq.Value,
  operator : String,
) -> @pgq.Value {
  let a = number_of(left)
  let b = number_of(right)
  match (a, b) {
    (Some(a), Some(b)) => {
      let both_int = left is @pgq.Value::Int(_) && right is @pgq.Value::Int(_)
      match operator {
        "+" =>
          if both_int {
            @pgq.Value::Int(a.to_int64() + b.to_int64())
          } else {
            @pgq.Value::Double(a + b)
          }
        "-" =>
          if both_int {
            @pgq.Value::Int(a.to_int64() - b.to_int64())
          } else {
            @pgq.Value::Double(a - b)
          }
        "*" =>
          if both_int {
            @pgq.Value::Int(a.to_int64() * b.to_int64())
          } else {
            @pgq.Value::Double(a * b)
          }
        "/" =>
          if both_int && b != 0.0 {
            @pgq.Value::Int(a.to_int64() / b.to_int64())
          } else if b == 0.0 {
            @pgq.Value::Nil
          } else {
            @pgq.Value::Double(a / b)
          }
        "%" =>
          if b == 0.0 {
            @pgq.Value::Nil
          } else if both_int {
            @pgq.Value::Int(a.to_int64() % b.to_int64())
          } else {
            @pgq.Value::Double(a % b)
          }
        "^" => @pgq.Value::Double(pow(a, b))
        _ => @pgq.Value::Nil
      }
    }
    _ => @pgq.Value::Nil
  }
}

///|
fn pow(base : Double, exponent : Double) -> Double {
  // An integer exponent needs nothing but multiplication, which keeps the
  // result exact for the squares and cubes a query asks for.
  let mut whole = exponent.to_int()
  let mut result = 1.0
  let mut factor = base
  let mut negative = false
  if whole < 0 {
    negative = true
    whole = -whole
  }
  while whole > 0 {
    if whole % 2 == 1 {
      result = result * factor
    }
    factor = factor * factor
    whole = whole / 2
  }
  if negative {
    1.0 / result
  } else {
    result
  }
}

///|
/// The functions of the expression language that are not aggregates.
fn Session::call(
  self : Session,
  row : Row,
  name : String,
  args : Array[Expr],
) -> @pgq.Value {
  let values = args.map(fn(arg) { self.eval(row, arg) })
  if name == "labels" {
    return match values.get(0) {
      Some(@pgq.Value::Vertex(vertex)) =>
        @pgq.Value::List([@pgq.Value::Text(vertex.label())])
      Some(@pgq.Value::Edge(edge)) =>
        @pgq.Value::List([@pgq.Value::Text(edge.label())])
      _ => @pgq.Value::List([])
    }
  }
  if name == "type" {
    return match values.get(0) {
      Some(@pgq.Value::Edge(edge)) => @pgq.Value::Text(edge.label())
      _ => @pgq.Value::Nil
    }
  }
  if name == "id" {
    return match values.get(0) {
      Some(@pgq.Value::Vertex(vertex)) => vertex.id()
      Some(@pgq.Value::Edge(edge)) => edge.id()
      _ => @pgq.Value::Nil
    }
  }
  if name == "size" || name == "length" {
    return match values.get(0) {
      Some(@pgq.Value::List(items)) =>
        @pgq.Value::Int(items.length().to_int64())
      Some(@pgq.Value::Text(text)) => @pgq.Value::Int(text.length().to_int64())
      // A path's length is the number of relationships it walked, not the
      // number of elements it visited.
      Some(@pgq.Value::Path(path)) =>
        @pgq.Value::Int(
          path
          .objects()
          .filter(fn(object) { object is @pgq.Value::Edge(_) })
          .length()
          .to_int64(),
        )
      Some(@pgq.Value::Dict(entries)) =>
        @pgq.Value::Int(entries.length().to_int64())
      _ => @pgq.Value::Nil
    }
  }
  if name == "keys" {
    return match values.get(0) {
      Some(@pgq.Value::Dict(entries)) =>
        @pgq.Value::List(entries.map(fn(entry) { entry.0 }))
      Some(@pgq.Value::Vertex(vertex)) =>
        @pgq.Value::List(
          vertex.properties().map(fn(entry) { @pgq.Value::Text(entry.0) }),
        )
      Some(@pgq.Value::Edge(edge)) =>
        @pgq.Value::List(
          edge.properties().map(fn(entry) { @pgq.Value::Text(entry.0) }),
        )
      _ => @pgq.Value::Nil
    }
  }
  if name == "nodes" {
    return match values.get(0) {
      Some(@pgq.Value::Path(path)) =>
        @pgq.Value::List(
          path.objects().filter(fn(object) { object is @pgq.Value::Vertex(_) }),
        )
      _ => @pgq.Value::Nil
    }
  }
  if name == "relationships" {
    return match values.get(0) {
      Some(@pgq.Value::Path(path)) =>
        @pgq.Value::List(
          path.objects().filter(fn(object) { object is @pgq.Value::Edge(_) }),
        )
      _ => @pgq.Value::Nil
    }
  }
  if name == "coalesce" {
    for value in values {
      if !(value is @pgq.Value::Nil) {
        return value
      }
    }
    return @pgq.Value::Nil
  }
  if name == "head" {
    return match values.get(0) {
      Some(@pgq.Value::List(items)) => items.get(0).unwrap_or(@pgq.Value::Nil)
      _ => @pgq.Value::Nil
    }
  }
  if name == "last" {
    return match values.get(0) {
      Some(@pgq.Value::List(items)) =>
        items.get(items.length() - 1).unwrap_or(@pgq.Value::Nil)
      _ => @pgq.Value::Nil
    }
  }
  if name == "tointeger" {
    return match values.get(0) {
      Some(@pgq.Value::Int(number)) => @pgq.Value::Int(number)
      Some(@pgq.Value::Double(number)) => @pgq.Value::Int(number.to_int64())
      Some(@pgq.Value::Text(text)) => @pgq.Value::Int(parse_integer(text))
      Some(@pgq.Value::Bool(flag)) =>
        @pgq.Value::Int(if flag { 1L } else { 0L })
      _ => @pgq.Value::Nil
    }
  }
  if name == "tofloat" {
    return match values.get(0) {
      Some(number) =>
        number_of(number)
        .map(fn(value) { @pgq.Value::Double(value) })
        .unwrap_or(@pgq.Value::Nil)
      None => @pgq.Value::Nil
    }
  }
  if name == "tostring" {
    return match values.get(0) {
      Some(@pgq.Value::Nil) => @pgq.Value::Nil
      Some(value) => @pgq.Value::Text(text_of(value))
      None => @pgq.Value::Nil
    }
  }
  if name == "abs" {
    return match values.get(0) {
      Some(@pgq.Value::Int(number)) =>
        @pgq.Value::Int(if number < 0L { -number } else { number })
      Some(@pgq.Value::Double(number)) =>
        @pgq.Value::Double(if number < 0.0 { -number } else { number })
      _ => @pgq.Value::Nil
    }
  }
  if name == "round" || name == "floor" || name == "ceil" {
    return match values.get(0) {
      Some(number) =>
        match number_of(number) {
          Some(value) =>
            @pgq.Value::Double(
              if name == "round" {
                round_half_up(value)
              } else if name == "floor" {
                floor_of(value)
              } else {
                ceil_of(value)
              },
            )
          None => @pgq.Value::Nil
        }
      None => @pgq.Value::Nil
    }
  }
  if name == "range" {
    let start = values.get(0).bind(number_of).unwrap_or(0.0)
    let stop = values.get(1).bind(number_of).unwrap_or(0.0)
    let step = values.get(2).bind(number_of).unwrap_or(1.0)
    let items : Array[@pgq.Value] = []
    if step != 0.0 {
      let mut cursor = start
      if step > 0.0 {
        while cursor <= stop {
          items.push(
            if cursor == cursor.to_int().to_double() {
              @pgq.Value::Int(cursor.to_int64())
            } else {
              @pgq.Value::Double(cursor)
            },
          )
          cursor = cursor + step
        }
      } else {
        while cursor >= stop {
          items.push(
            if cursor == cursor.to_int().to_double() {
              @pgq.Value::Int(cursor.to_int64())
            } else {
              @pgq.Value::Double(cursor)
            },
          )
          cursor = cursor + step
        }
      }
    }
    return @pgq.Value::List(items)
  }
  if name == "exists" {
    return match values.get(0) {
      Some(@pgq.Value::Nil) => @pgq.Value::Bool(false)
      Some(_) => @pgq.Value::Bool(true)
      None => @pgq.Value::Bool(false)
    }
  }
  @pgq.Value::Nil
}

///|
fn round_half_up(value : Double) -> Double {
  if value < 0.0 {
    -floor_of(-value + 0.5)
  } else {
    floor_of(value + 0.5)
  }
}

///|
fn floor_of(value : Double) -> Double {
  let whole = value.to_int()
  let truncated = whole.to_double()
  if truncated > value {
    truncated - 1.0
  } else {
    truncated
  }
}

///|
fn ceil_of(value : Double) -> Double {
  let whole = value.to_int()
  let truncated = whole.to_double()
  if truncated < value {
    truncated + 1.0
  } else {
    truncated
  }
}

///|
fn parse_integer(text : String) -> Int64 {
  let mut total = 0L
  let mut negative = false
  for index in 0..<text.length() {
    let ch = text.get_char(index).unwrap_or(' ')
    if ch == '-' && index == 0 {
      negative = true
    } else if ch >= '0' && ch <= '9' {
      total = total * 10L + (ch.to_int().to_int64() - '0'.to_int().to_int64())
    }
  }
  if negative {
    -total
  } else {
    total
  }
}
