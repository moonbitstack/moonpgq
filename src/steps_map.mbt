// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// `values(keys)`: every value of the named properties, in property order.
fn step_values(
  _ctx : Ctx,
  input : Array[Traverser],
  keys : Array[String],
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let element = require_element("values()", traverser.value)
    for entry in element.properties() {
      if keys.is_empty() || keys.contains(entry.0) {
        for value in entry.1 {
          out.push(advance(traverser, value))
        }
      }
    }
  }
  out
}

///|
/// `valueMap()`: a map from property key to its values. A vertex keeps every
/// value of a key in a list, an edge has one value per key.
fn step_value_map(
  ctx : Ctx,
  input : Array[Traverser],
  keys : Array[String],
  bys : Array[By],
  with_tokens : Bool,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let element = require_element("valueMap()", traverser.value)
    let entries : Array[(Value, Value)] = []
    if with_tokens {
      entries.push((Value::Text("id"), element.id()))
      entries.push((Value::Text("label"), Value::Text(element.label())))
    }
    for entry in element.properties() {
      if keys.is_empty() || keys.contains(entry.0) {
        let gathered = match element {
          Vertex(_) => Value::List(entry.1)
          _ =>
            if entry.1.length() == 1 {
              entry.1[0]
            } else {
              Value::List(entry.1)
            }
        }
        let mapped = if bys.is_empty() {
          gathered
        } else {
          read_by_at(ctx, bys, entries.length(), gathered)
        }
        entries.push((Value::Text(entry.0), mapped))
      }
    }
    out.push(advance(traverser, Value::Dict(entries)))
  }
  out
}

///|
/// `elementMap()`: id, label and properties, with a single value per key
/// unless the key holds several.
fn step_element_map(
  ctx : Ctx,
  input : Array[Traverser],
  keys : Array[String],
  bys : Array[By],
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let element = require_element("elementMap()", traverser.value)
    let entries : Array[(Value, Value)] = []
    entries.push((Value::Text("id"), element.id()))
    entries.push((Value::Text("label"), Value::Text(element.label())))
    for entry in element.properties() {
      if keys.is_empty() || keys.contains(entry.0) {
        let gathered = if entry.1.length() == 1 {
          entry.1[0]
        } else {
          Value::List(entry.1)
        }
        let mapped = if bys.is_empty() {
          gathered
        } else {
          read_by_at(ctx, bys, entries.length(), gathered)
        }
        entries.push((Value::Text(entry.0), mapped))
      }
    }
    out.push(advance(traverser, Value::Dict(entries)))
  }
  out
}

///|
/// `propertyMap()`: a map from property key to the properties themselves.
fn step_property_map(
  ctx : Ctx,
  input : Array[Traverser],
  keys : Array[String],
  bys : Array[By],
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let element = require_element("propertyMap()", traverser.value)
    let entries : Array[(Value, Value)] = []
    for entry in element.properties() {
      if keys.is_empty() || keys.contains(entry.0) {
        let properties = Value::List(
          entry.1.map(fn(value) {
            Value::Property(Property::new(entry.0, value))
          }),
        )
        let mapped = if bys.is_empty() {
          properties
        } else {
          read_by_at(ctx, bys, entries.length(), properties)
        }
        entries.push((Value::Text(entry.0), mapped))
      }
    }
    out.push(advance(traverser, Value::Dict(entries)))
  }
  out
}

///|
/// `properties(keys)`: the properties of an element, one value at a time.
fn step_properties(
  ctx : Ctx,
  input : Array[Traverser],
  keys : Array[String],
  bys : Array[By],
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let element = require_element("properties()", traverser.value)
    for entry in element.properties() {
      if keys.is_empty() || keys.contains(entry.0) {
        for value in entry.1 {
          let property = Value::Property(Property::new(entry.0, value))
          let mapped = if bys.is_empty() {
            property
          } else {
            read_by_at(ctx, bys, 0, property)
          }
          out.push(advance(traverser, mapped))
        }
      }
    }
  }
  out
}

///|
fn step_element_key(_ctx : Ctx, input : Array[Traverser]) -> Array[Traverser] {
  let out : Array[Traverser] = []
  for traverser in input {
    match traverser.value {
      Property(property) =>
        out.push(advance(traverser, Value::Text(property.key())))
      _ => ()
    }
  }
  out
}

///|
fn step_element_value(_ctx : Ctx, input : Array[Traverser]) -> Array[Traverser] {
  let out : Array[Traverser] = []
  for traverser in input {
    match traverser.value {
      Property(property) => out.push(advance(traverser, property.value()))
      _ => ()
    }
  }
  out
}

///|
fn step_element_label(_ctx : Ctx, input : Array[Traverser]) -> Array[Traverser] {
  let out : Array[Traverser] = []
  for traverser in input {
    match traverser.value {
      Vertex(vertex) =>
        out.push(advance(traverser, Value::Text(vertex.label())))
      Edge(edge) => out.push(advance(traverser, Value::Text(edge.label())))
      _ => ()
    }
  }
  out
}

///|
fn step_element_id(_ctx : Ctx, input : Array[Traverser]) -> Array[Traverser] {
  let out : Array[Traverser] = []
  for traverser in input {
    match traverser.value {
      Vertex(vertex) => out.push(advance(traverser, vertex.id()))
      Edge(edge) => out.push(advance(traverser, edge.id()))
      _ => ()
    }
  }
  out
}

///|
/// `unfold()`: the items of a list, the entries of a map, nothing else.
fn step_unfold(_ctx : Ctx, input : Array[Traverser]) -> Array[Traverser] {
  let out : Array[Traverser] = []
  for traverser in input {
    match traverser.value {
      List(items) =>
        for item in items {
          out.push(advance(traverser, item))
        }
      Dict(entries) =>
        for entry in entries {
          out.push(advance(traverser, Value::Entry(entry.0, entry.1)))
        }
      other => out.push(advance(traverser, other))
    }
  }
  out
}

///|
/// `path()`: the walk each traverser took, mapped through the `by()` list.
fn step_path(
  ctx : Ctx,
  input : Array[Traverser],
  bys : Array[By],
  from : By?,
  to : By?,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let first = path_mark(traverser, from).unwrap_or(0)
    let last = path_mark(traverser, to).unwrap_or(traverser.path.length() - 1)
    let objects : Array[Value] = []
    let mut index = first
    while index <= last && index < traverser.path.length() {
      if index >= 0 {
        let value = traverser.path[index]
        let mapped = if bys.is_empty() {
          value
        } else {
          read_by_at(ctx, bys, index - first, value)
        }
        objects.push(mapped)
      }
      index = index + 1
    }
    out.push(advance(traverser, Value::Path(Path::new(objects))))
  }
  out
}

///|
/// Where a `from()` or `to()` of `path()` points: the position the label was
/// attached to. A traversal argument is evaluated against the current value and
/// the result is looked for in the walk.
fn path_mark(traverser : Traverser, mark : By?) -> Int32? {
  match mark {
    None => None
    Some(by) =>
      match by.key {
        Some(name) =>
          traverser.labels
          .filter(fn(entry) { entry.0 == name })
          .get(0)
          .map(fn(entry) { entry.1 })
        None => None
      }
  }
}

///|
/// `select(keys)`: the values bound to labels, or the columns of a map.
fn step_select(
  ctx : Ctx,
  input : Array[Traverser],
  keys : Array[SelectKey],
  bys : Array[By],
  pop : Pop,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    if keys.length() == 1 {
      let value = match keys[0] {
        Name(name) =>
          match lookup_label(traverser, name, pop) {
            Some(value) => value
            None => continue
          }
        Column(column) =>
          match read_column(traverser.value, column) {
            Some(value) => value
            None => continue
          }
      }
      let mapped = if bys.is_empty() {
        value
      } else {
        read_by_at(ctx, bys, 0, value)
      }
      out.push(advance(traverser, mapped))
    } else {
      let entries : Array[(Value, Value)] = []
      let mut complete = true
      for key in keys {
        let value = match key {
          Name(name) =>
            match lookup_label(traverser, name, pop) {
              Some(value) => value
              None => {
                complete = false
                Value::Nil
              }
            }
          Column(column) =>
            match read_column(traverser.value, column) {
              Some(value) => value
              None => {
                complete = false
                Value::Nil
              }
            }
        }
        entries.push((Value::Text(key.to_text()), value))
      }
      if complete {
        out.push(advance(traverser, Value::Dict(entries)))
      }
    }
  }
  out
}

///|
fn read_column(value : Value, column : Column) -> Value? {
  match value {
    Dict(entries) =>
      if column == Column::Keys {
        Some(Value::List(entries.map(fn(entry) { entry.0 })))
      } else {
        Some(Value::List(entries.map(fn(entry) { entry.1 })))
      }
    Entry(key, value) =>
      if column == Column::Keys {
        Some(key)
      } else {
        Some(value)
      }
    _ => None
  }
}

///|
/// `project(keys)`: a map from each key to the value its `by()` produces.
fn step_project(
  ctx : Ctx,
  input : Array[Traverser],
  keys : Array[String],
  bys : Array[By],
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let entries : Array[(Value, Value)] = []
    for index in 0..<keys.length() {
      let mapped = if bys.is_empty() {
        traverser.value
      } else {
        read_by_at(ctx, bys, index, traverser.value)
      }
      entries.push((Value::Text(keys[index]), mapped))
    }
    out.push(advance(traverser, Value::Dict(entries)))
  }
  out
}

///|
/// `map(traversal)`: the first result of the inner traversal.
fn step_map(
  ctx : Ctx,
  input : Array[Traverser],
  inner : Traversal,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    match run_on(ctx, inner, traverser) {
      [first, ..] => out.push(first)
      _ => ()
    }
  }
  out
}

///|
/// `flatMap(traversal)`: every result of the inner traversal.
fn step_flat_map(
  ctx : Ctx,
  input : Array[Traverser],
  inner : Traversal,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    for result in run_on(ctx, inner, traverser) {
      out.push(result)
    }
  }
  out
}

///|
/// `local(traversal)`: the inner traversal sees one traverser at a time, so its
/// barriers do not merge the stream.
fn step_local(
  ctx : Ctx,
  input : Array[Traverser],
  inner : Traversal,
) -> Array[Traverser] raise Refused {
  step_flat_map(ctx, input, inner)
}
