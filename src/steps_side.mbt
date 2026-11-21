// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn step_count(
  _ctx : Ctx,
  input : Array[Traverser],
  scope : Scope,
) -> Array[Traverser] {
  if scope == Scope::Global {
    return [start_traverser(Value::Int(input.length().to_int64()))]
  }
  let out : Array[Traverser] = []
  for traverser in input {
    let count = match traverser.value {
      List(items) => items.length()
      Dict(entries) => entries.length()
      Text(text) => text.length()
      _ => 1
    }
    out.push(advance(traverser, Value::Int(count.to_int64())))
  }
  out
}

///|
/// The numbers a reducing step works on, after the `by()` mapping.
fn numbers_of(
  ctx : Ctx,
  traversers : Array[Traverser],
  bys : Array[By],
) -> Array[Double] raise Refused {
  let out : Array[Double] = []
  for traverser in traversers {
    let value = if bys.is_empty() {
      traverser.value
    } else {
      read_by_at(ctx, bys, 0, traverser.value)
    }
    match value.as_double() {
      Some(number) => out.push(number)
      None => ()
    }
  }
  out
}

///|
fn mapped_values(
  ctx : Ctx,
  input : Array[Traverser],
  bys : Array[By],
) -> Array[Value] raise Refused {
  let out : Array[Value] = []
  for traverser in input {
    out.push(
      if bys.is_empty() {
        traverser.value
      } else {
        read_by_at(ctx, bys, 0, traverser.value)
      },
    )
  }
  out
}

///|
fn step_sum(
  ctx : Ctx,
  input : Array[Traverser],
  scope : Scope,
  bys : Array[By],
) -> Array[Traverser] raise Refused {
  if scope == Scope::Global {
    let values = mapped_values(ctx, input, bys)
    let mut int_total = 0L
    let mut double_total = 0.0
    let mut any_double = false
    let mut counted = 0
    for value in values {
      match value {
        Int(number) => {
          int_total = int_total + number
          double_total = double_total + number.to_double()
          counted = counted + 1
        }
        Double(number) => {
          any_double = true
          double_total = double_total + number
          counted = counted + 1
        }
        _ => ()
      }
    }
    if counted == 0 {
      return []
    }
    return [
      start_traverser(
        if any_double {
          Value::Double(double_total)
        } else {
          Value::Int(int_total)
        },
      ),
    ]
  }
  let out : Array[Traverser] = []
  for traverser in input {
    match traverser.value {
      List(items) => {
        let total = items
          .filter_map(fn(item) { item.as_double() })
          .fold(init=0.0, fn(a, b) { a + b })
        out.push(advance(traverser, Value::Double(total)))
      }
      _ => out.push(traverser)
    }
  }
  out
}

///|
fn step_mean(
  ctx : Ctx,
  input : Array[Traverser],
  scope : Scope,
  bys : Array[By],
) -> Array[Traverser] raise Refused {
  if scope == Scope::Global {
    let numbers = numbers_of(ctx, input, bys)
    if numbers.is_empty() {
      return []
    }
    let total = numbers.fold(init=0.0, fn(a, b) { a + b })
    return [
      start_traverser(Value::Double(total / numbers.length().to_double())),
    ]
  }
  let out : Array[Traverser] = []
  for traverser in input {
    match traverser.value {
      List(items) => {
        let numbers = items.filter_map(fn(item) { item.as_double() })
        let value = if numbers.is_empty() {
          Value::Nil
        } else {
          let total = numbers.fold(init=0.0, fn(a, b) { a + b })
          Value::Double(total / numbers.length().to_double())
        }
        out.push(advance(traverser, value))
      }
      _ => out.push(traverser)
    }
  }
  out
}

///|
fn step_extreme(
  ctx : Ctx,
  input : Array[Traverser],
  scope : Scope,
  bys : Array[By],
  want_max : Bool,
) -> Array[Traverser] raise Refused {
  if scope == Scope::Global {
    let mut best : Value? = None
    for traverser in input {
      let value = if bys.is_empty() {
        traverser.value
      } else {
        read_by_at(ctx, bys, 0, traverser.value)
      }
      guard value != Value::Nil else { continue }
      best = match best {
        None => Some(value)
        Some(current) =>
          if want_max {
            if value.compare(current) > 0 {
              Some(value)
            } else {
              Some(current)
            }
          } else if value.compare(current) < 0 {
            Some(value)
          } else {
            Some(current)
          }
      }
    }
    match best {
      Some(value) => return [start_traverser(value)]
      None => return []
    }
  }
  let out : Array[Traverser] = []
  for traverser in input {
    match traverser.value {
      List(items) => {
        let mut best : Value? = None
        for item in items {
          guard item != Value::Nil else { continue }
          best = match best {
            None => Some(item)
            Some(current) =>
              if want_max {
                if item.compare(current) > 0 {
                  Some(item)
                } else {
                  Some(current)
                }
              } else if item.compare(current) < 0 {
                Some(item)
              } else {
                Some(current)
              }
          }
        }
        out.push(advance(traverser, best.unwrap_or(Value::Nil)))
      }
      _ => out.push(traverser)
    }
  }
  out
}

///|
fn step_fold(input : Array[Traverser], scope : Scope) -> Array[Traverser] {
  if scope == Scope::Global {
    return [
      start_traverser(Value::List(input.map(fn(traverser) { traverser.value }))),
    ]
  }
  input.map(fn(traverser) { advance(traverser, Value::List([traverser.value])) })
}

///|
/// `order()`: a stable sort by the `by()` list, from the first comparator that
/// tells two values apart.
fn step_order(
  ctx : Ctx,
  input : Array[Traverser],
  scope : Scope,
  comparators : Array[Comparator],
) -> Array[Traverser] {
  if comparators.any(fn(comparator) { comparator.order == Order::Shuffle }) {
    // A shuffled order is asserted as unordered, so any fixed order will do
    // and the result stays comparable between runs.
    return input.rev_iter().to_array()
  }
  if scope == Scope::Local {
    let out : Array[Traverser] = []
    for traverser in input {
      match traverser.value {
        List(items) => {
          let sorted = items.copy()
          sorted.sort_by(fn(left, right) {
            compare_by(ctx, comparators, left, right)
          })
          out.push(advance(traverser, Value::List(sorted)))
        }
        _ => out.push(traverser)
      }
    }
    return out
  }
  let comparators = if comparators.is_empty() {
    [Comparator::of(By::identity())]
  } else {
    comparators
  }
  let out = input.copy()
  out.sort_by(fn(left, right) {
    compare_by(ctx, comparators, left.value, right.value)
  })
  out
}

///|
fn compare_by(
  ctx : Ctx,
  comparators : Array[Comparator],
  left : Value,
  right : Value,
) -> Int32 {
  for comparator in comparators {
    let left_key = try_read_by(ctx, comparator.by, left)
    let right_key = try_read_by(ctx, comparator.by, right)
    let order = left_key.compare(right_key)
    if order != 0 {
      return if comparator.order == Order::Desc { -order } else { order }
    }
  }
  0
}

///|
/// Reading through a `by()` only fails when the nested traversal is malformed;
/// ordering then treats the value as absent rather than losing the whole sort.
fn try_read_by(ctx : Ctx, by : By, value : Value) -> Value {
  read_by(ctx, by, value) catch {
    _ => Value::Nil
  }
}

///|
fn index_of_value(values : Array[Value], want : Value) -> Int32 {
  for index in 0..<values.length() {
    if values[index].equals(want) {
      return index
    }
  }
  -1
}

///|
/// `group()`: one entry per distinct key, holding the values grouped under it.
fn step_group(
  ctx : Ctx,
  input : Array[Traverser],
  key : String?,
  comparators : Array[Comparator],
) -> Array[Traverser] raise Refused {
  let key_by = comparators
    .get(0)
    .map(fn(comparator) { comparator.by })
    .unwrap_or(By::identity())
  let value_by = comparators.get(1).map(fn(comparator) { comparator.by })
  let keys : Array[Value] = []
  let groups : Array[Array[Traverser]] = []
  for traverser in input {
    let group_key = read_by(ctx, key_by, traverser.value)
    match array_find(keys, fn(existing) { existing.equals(group_key) }) {
      Some(_) => {
        let index = index_of_value(keys, group_key)
        groups[index].push(traverser)
      }
      None => {
        keys.push(group_key)
        groups.push([traverser])
      }
    }
  }
  let entries : Array[(Value, Value)] = []
  for index in 0..<keys.length() {
    let items = groups[index]
    let value = match value_by {
      None => Value::List(items.map(fn(item) { item.value }))
      Some(by) =>
        match by.traversal {
          Some(traversal) => {
            let results = run_steps(ctx, items, traversal, 0)
            if is_reducing(traversal) {
              match results {
                [first, ..] => first.value
                _ => Value::List([])
              }
            } else {
              Value::List(results.map(fn(result) { result.value }))
            }
          }
          None =>
            Value::List(
              items.map(fn(item) raise Refused { read_by(ctx, by, item.value) }),
            )
        }
    }
    entries.push((keys[index], value))
  }
  let grouped = Value::Dict(entries)
  match key {
    Some(name) => {
      ctx.effects.push((name, [grouped]))
      []
    }
    None => [start_traverser(grouped)]
  }
}

///|
fn is_reducing(traversal : Traversal) -> Bool {
  match traversal.steps.get(traversal.steps.length() - 1) {
    Some(Count(_))
    | Some(Sum(_, _))
    | Some(Mean(_, _))
    | Some(Max(_, _))
    | Some(Min(_, _))
    | Some(Fold(_))
    | Some(Group(_, _))
    | Some(GroupCount(_, _)) => true
    _ => false
  }
}

///|
fn step_group_count(
  ctx : Ctx,
  input : Array[Traverser],
  key : String?,
  by : By?,
) -> Array[Traverser] raise Refused {
  let keys : Array[Value] = []
  let counts : Array[Int64] = []
  for traverser in input {
    let mapped = match by {
      Some(by) => read_by(ctx, by, traverser.value)
      None => traverser.value
    }
    match array_find(keys, fn(existing) { existing.equals(mapped) }) {
      Some(_) => {
        let index = index_of_value(keys, mapped)
        counts[index] = counts[index] + 1L
      }
      None => {
        keys.push(mapped)
        counts.push(1L)
      }
    }
  }
  let entries : Array[(Value, Value)] = []
  for index in 0..<keys.length() {
    entries.push((keys[index], Value::Int(counts[index])))
  }
  let counted = Value::Dict(entries)
  match key {
    Some(name) => {
      ctx.effects.push((name, [counted]))
      []
    }
    None => [start_traverser(counted)]
  }
}

///|
/// `aggregate()` and `store()`: collect the values into a side effect and pass
/// the traversers on. Both are here; they differ only in when the collection is
/// read, and a traversal that caps the key sees the same contents.
fn step_collect(
  ctx : Ctx,
  input : Array[Traverser],
  key : String,
  scope : Scope,
  by : By?,
) -> Array[Traverser] raise Refused {
  for traverser in input {
    match scope {
      Scope::Global => {
        let value = match by {
          Some(by) => read_by(ctx, by, traverser.value)
          None => traverser.value
        }
        ctx.push_effect(key, value)
      }
      Scope::Local =>
        match (traverser.value, by) {
          (List(items), Some(by)) =>
            for item in items {
              ctx.push_effect(key, read_by(ctx, by, item))
            }
          (List(items), None) =>
            for item in items {
              ctx.push_effect(key, item)
            }
          (value, Some(by)) => ctx.push_effect(key, read_by(ctx, by, value))
          (value, None) => ctx.push_effect(key, value)
        }
    }
  }
  input
}
