// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn filter_has_label(
  input : Array[Traverser],
  labels : Array[String],
) -> Array[Traverser] {
  input.filter(fn(traverser) {
    match traverser.value.element() {
      Some(element) => labels.contains(element.label())
      None => false
    }
  })
}

///|
fn filter_has_id(
  input : Array[Traverser],
  ids : Array[Value],
) -> Array[Traverser] {
  input.filter(fn(traverser) {
    match id_of(traverser.value) {
      Some(id) => ids.any(fn(want) { id.equals(want) })
      None => false
    }
  })
}

///|
fn filter_has_key(
  input : Array[Traverser],
  keys : Array[String],
) -> Array[Traverser] {
  input.filter(fn(traverser) {
    match traverser.value.element() {
      Some(element) =>
        element.properties().any(fn(entry) { keys.contains(entry.0) })
      None => false
    }
  })
}

///|
fn filter_has_value(
  input : Array[Traverser],
  values : Array[Value],
) -> Array[Traverser] {
  input.filter(fn(traverser) {
    match traverser.value.element() {
      Some(element) =>
        element
        .properties()
        .any(fn(entry) {
          entry.1.any(fn(value) { values.any(fn(want) { value.equals(want) }) })
        })
      None => false
    }
  })
}

///|
fn filter_has(input : Array[Traverser], has : Has) -> Array[Traverser] {
  input.filter(fn(traverser) {
    match traverser.value.element() {
      Some(element) =>
        element
        .properties()
        .any(fn(entry) {
          entry.0 == has.key &&
          entry.1.any(fn(value) { has.predicate.accepts(value) })
        })
      None => false
    }
  })
}

///|
fn filter_has_not(
  input : Array[Traverser],
  keys : Array[String],
) -> Array[Traverser] {
  input.filter(fn(traverser) {
    match traverser.value.element() {
      Some(element) =>
        !element.properties().any(fn(entry) { keys.contains(entry.0) })
      None => false
    }
  })
}

///|
fn filter_is(
  input : Array[Traverser],
  predicate : Predicate,
) -> Array[Traverser] {
  input.filter(fn(traverser) { predicate.accepts(traverser.value) })
}

///|
/// `simplePath()` keeps walks that never revisit a value, `cyclicPath()` keeps
/// the ones that do.
fn filter_simple_path(
  input : Array[Traverser],
  simple : Bool,
) -> Array[Traverser] {
  input.filter(fn(traverser) {
    let seen : Array[String] = []
    let mut repeated = false
    for value in traverser.path {
      let key = value.key()
      if seen.contains(key) {
        repeated = true
      }
      seen.push(key)
    }
    if simple {
      !repeated
    } else {
      repeated
    }
  })
}

///|
/// `limit()`, `skip()` and `range()` are one step with different bounds: `high`
/// of -1 means "to the end".
fn step_range(
  _ctx : Ctx,
  input : Array[Traverser],
  low : Int64,
  high : Int64,
  scope : Scope,
) -> Array[Traverser] {
  if scope == Scope::Global {
    let end = if high < 0 {
      input.length().to_int64()
    } else if high > input.length().to_int64() {
      input.length().to_int64()
    } else {
      high
    }
    let out : Array[Traverser] = []
    let mut index = if low < 0 { 0L } else { low }
    while index < end {
      out.push(input[index.to_int()])
      index = index + 1
    }
    return out
  }
  let out : Array[Traverser] = []
  for traverser in input {
    match traverser.value {
      List(items) => {
        let sliced = slice_array(items, low, high)
        out.push(advance(traverser, Value::List(sliced)))
      }
      _ => out.push(traverser)
    }
  }
  out
}

///|
fn slice_traversers(
  input : Array[Traverser],
  low : Int64,
  high : Int64,
) -> Array[Traverser] {
  let end = if high < 0 || high > input.length().to_int64() {
    input.length().to_int64()
  } else {
    high
  }
  let out : Array[Traverser] = []
  let mut index = if low < 0 { 0L } else { low }
  while index < end {
    match input.get(index.to_int()) {
      Some(traverser) => out.push(traverser)
      None => ()
    }
    index = index + 1
  }
  out
}

///|
fn slice_array(items : Array[Value], low : Int64, high : Int64) -> Array[Value] {
  let end = if high < 0 || high > items.length().to_int64() {
    items.length().to_int64()
  } else {
    high
  }
  let out : Array[Value] = []
  let mut index = if low < 0 { 0L } else { low }
  while index < end {
    match items.get(index.to_int()) {
      Some(item) => out.push(item)
      None => ()
    }
    index = index + 1
  }
  out
}

///|
fn step_tail(
  _ctx : Ctx,
  input : Array[Traverser],
  amount : Int64,
  scope : Scope,
) -> Array[Traverser] {
  if scope == Scope::Global {
    let count = input.length().to_int64()
    let start = if amount >= count { 0L } else { count - amount }
    return slice_traversers(input, start, -1L)
  }
  let out : Array[Traverser] = []
  for traverser in input {
    match traverser.value {
      List(items) => {
        let start = if amount >= items.length().to_int64() {
          0L
        } else {
          items.length().to_int64() - amount
        }
        out.push(
          advance(traverser, Value::List(slice_array(items, start, -1L))),
        )
      }
      _ => out.push(traverser)
    }
  }
  out
}

///|
/// `dedup()`: the first traverser for each distinct value, or for each distinct
/// tuple of labelled values or `by()` results.
fn step_dedup(
  ctx : Ctx,
  input : Array[Traverser],
  labels : Array[String],
  bys : Array[By],
  scope : Scope,
) -> Array[Traverser] raise Refused {
  if scope == Scope::Local {
    let out : Array[Traverser] = []
    for traverser in input {
      match traverser.value {
        List(items) => {
          let seen : Array[String] = []
          let kept : Array[Value] = []
          for item in items {
            let key = read_by(ctx, bys.get(0).unwrap_or(By::identity()), item).key()
            if !seen.contains(key) {
              seen.push(key)
              kept.push(item)
            }
          }
          out.push(advance(traverser, Value::List(kept)))
        }
        _ => out.push(traverser)
      }
    }
    return out
  }
  let seen : Array[String] = []
  let out : Array[Traverser] = []
  for traverser in input {
    let key = dedup_key(ctx, traverser, labels, bys)
    if !seen.contains(key) {
      seen.push(key)
      out.push(traverser)
    }
  }
  out
}

///|
fn dedup_key(
  ctx : Ctx,
  traverser : Traverser,
  labels : Array[String],
  bys : Array[By],
) -> String raise Refused {
  if !labels.is_empty() {
    let parts : Array[String] = []
    for name in labels {
      let value = lookup_label(traverser, name, Pop::Last).unwrap_or(Value::Nil)
      parts.push(value.key())
    }
    return parts.join("|")
  }
  if !bys.is_empty() {
    let parts : Array[String] = []
    for index in 0..<bys.length() {
      parts.push(read_by(ctx, bys[index], traverser.value).key())
    }
    return parts.join("|")
  }
  traverser.value.key()
}

///|
fn filter_by_traversal(
  ctx : Ctx,
  input : Array[Traverser],
  inner : Traversal,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    if !run_on(ctx, inner, traverser).is_empty() {
      out.push(traverser)
    }
  }
  out
}

///|
fn filter_not(
  ctx : Ctx,
  input : Array[Traverser],
  inner : Traversal,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    if run_on(ctx, inner, traverser).is_empty() {
      out.push(traverser)
    }
  }
  out
}

///|
fn filter_and(
  ctx : Ctx,
  input : Array[Traverser],
  inners : Array[Traversal],
) -> Array[Traverser] raise Refused {
  let mut current = input
  for inner in inners {
    current = filter_by_traversal(ctx, current, inner)
  }
  current
}

///|
fn filter_or(
  ctx : Ctx,
  input : Array[Traverser],
  inners : Array[Traversal],
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    for inner in inners {
      if !run_on(ctx, inner, traverser).is_empty() {
        out.push(traverser)
        break
      }
    }
  }
  out
}

///|
fn filter_where(
  ctx : Ctx,
  input : Array[Traverser],
  kind : WhereKind,
) -> Array[Traverser] raise Refused {
  match kind {
    Traversal(inner) => filter_by_traversal(ctx, input, inner)
    Predicate(predicate) =>
      input.filter(fn(traverser) { predicate.accepts(traverser.value) })
    Label(name, predicate) => {
      let out : Array[Traverser] = []
      for traverser in input {
        match lookup_label(traverser, name, Pop::Last) {
          Some(value) =>
            if predicate
              .substitute(fn(operand) { resolve_operand(traverser, operand) })
              .accepts(value) {
              out.push(traverser)
            }
          None => ()
        }
      }
      out
    }
  }
}

///|
/// In `where("a", P.eq("b"))` the right side may name another label.
fn resolve_operand(traverser : Traverser, operand : Value) -> Value {
  match operand {
    Text(name) =>
      match lookup_label(traverser, name, Pop::Last) {
        Some(value) => value
        None => operand
      }
    _ => operand
  }
}

///|
/// Rewrites every value a predicate compares against.
fn Predicate::substitute(
  self : Predicate,
  rewrite : (Value) -> Value,
) -> Predicate {
  match self {
    Equal(value) => Equal(rewrite(value))
    NotEqual(value) => NotEqual(rewrite(value))
    Less(value) => Less(rewrite(value))
    LessEqual(value) => LessEqual(rewrite(value))
    Greater(value) => Greater(rewrite(value))
    GreaterEqual(value) => GreaterEqual(rewrite(value))
    Between(low, high) => Between(rewrite(low), rewrite(high))
    Inside(low, high) => Inside(rewrite(low), rewrite(high))
    Outside(low, high) => Outside(rewrite(low), rewrite(high))
    Within(values) => Within(values.map(rewrite))
    Without(values) => Without(values.map(rewrite))
    And(left, right) => And(left.substitute(rewrite), right.substitute(rewrite))
    Or(left, right) => Or(left.substitute(rewrite), right.substitute(rewrite))
    Not(inner) => Not(inner.substitute(rewrite))
    other => other
  }
}

///|
/// `sample(n)`: the first n values. Sampling is not random: a result that
/// depends on chance cannot be compared with one that does not, so the order
/// the stream already has is used and the caller who needs randomness orders by
/// a computed key.
fn step_sample(
  _ctx : Ctx,
  input : Array[Traverser],
  amount : Int64,
  scope : Scope,
) -> Array[Traverser] {
  if scope == Scope::Global {
    return slice_traversers(input, 0L, amount)
  }
  let out : Array[Traverser] = []
  for traverser in input {
    match traverser.value {
      List(items) =>
        out.push(
          advance(traverser, Value::List(slice_array(items, 0L, amount))),
        )
      _ => out.push(traverser)
    }
  }
  out
}
