// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The most rounds a `repeat()` without a bound is allowed. A traversal that
/// would loop forever is a mistake in the query, and stopping is friendlier than
/// never returning; the number is high enough that any real walk ends first.
const MAX_ROUNDS : Int32 = 64

///|
/// How many traversers one round of `repeat()` may carry. A body that both
/// walks out and walks in grows exponentially, and no store survives forty
/// rounds of it; the limit turns that into a refusal instead of a dead process.
const MAX_FRONTIER : Int32 = 20000

///|
/// `repeat()` with `until()`, `emit()` and `times()`. The body runs on the
/// frontier of the previous round, so a round is one breadth-first step of the
/// walk rather than a recursion per traverser.
fn step_repeat(
  ctx : Ctx,
  input : Array[Traverser],
  repeat : Repeat,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for start in input {
    let mut frontier : Array[Traverser] = [start]
    let mut round = 0
    let limit = repeat.times.unwrap_or(MAX_ROUNDS.to_int64())
    if repeat.emit_first {
      match repeat.emit {
        Some(emit) =>
          if !run_on(ctx, emit, start).is_empty() {
            out.push(start)
          }
        None => out.push(start)
      }
    }
    while !frontier.is_empty() && round.to_int64() < limit {
      round = round + 1
      let next : Array[Traverser] = []
      for traverser in frontier {
        let stopping = match repeat.until {
          Some(until) =>
            if repeat.until_first {
              !run_on(ctx, until, traverser).is_empty()
            } else {
              false
            }
          None => false
        }
        if stopping {
          out.push(traverser)
          continue
        }
        for produced in run_on(ctx, repeat.body, traverser) {
          let stepped = {
            value: produced.value,
            path: produced.path,
            labels: produced.labels,
            loops: round,
          }
          let emits = match repeat.emit {
            Some(emit) =>
              if repeat.emit_first {
                !run_on(ctx, emit, stepped).is_empty()
              } else {
                !run_on(ctx, emit, stepped).is_empty()
              }
            None => false
          }
          if emits {
            out.push(stepped)
          }
          let done = match repeat.until {
            Some(until) =>
              if repeat.until_first {
                false
              } else {
                !run_on(ctx, until, stepped).is_empty()
              }
            None => false
          }
          if done {
            match repeat.emit {
              None => out.push(stepped)
              Some(_) => ()
            }
          } else {
            next.push(stepped)
          }
        }
      }
      if next.length() > MAX_FRONTIER {
        raise Refused::Unsupported(
          "repeat()", "the frontier grew past the limit",
        )
      }
      frontier = next
    }
    if repeat.until is None {
      for traverser in frontier {
        out.push(traverser)
      }
    }
  }
  out
}

///|
/// `coalesce(traversals)`: the results of the first child that produces any.
fn step_coalesce(
  ctx : Ctx,
  input : Array[Traverser],
  inners : Array[Traversal],
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    for inner in inners {
      let produced = run_on(ctx, inner, traverser)
      if !produced.is_empty() {
        for result in produced {
          out.push(result)
        }
        break
      }
    }
  }
  out
}

///|
/// `optional(traversal)`: the child's results, or the traverser unchanged when
/// the child produces nothing.
fn step_optional(
  ctx : Ctx,
  input : Array[Traverser],
  inner : Traversal,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let produced = run_on(ctx, inner, traverser)
    if produced.is_empty() {
      out.push(traverser)
    } else {
      for result in produced {
        out.push(result)
      }
    }
  }
  out
}

///|
/// `union(traversals)`: every child applied to every traverser, one after the
/// other.
fn step_union(
  ctx : Ctx,
  input : Array[Traverser],
  inners : Array[Traversal],
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    for inner in inners {
      for result in run_on(ctx, inner, traverser) {
        out.push(result)
      }
    }
  }
  out
}

///|
/// `choose()`: a trailer that picks a branch per traverser, by a predicate, by
/// whether a child traversal produces anything, or by a value looked up in the
/// options.

///|
/// The branch an `option()` list picks for a value: an exact match, else the
/// first predicate the value satisfies, else the default branch.
fn option_branch(choose : Choose, key : Value) -> Traversal? {
  for option in choose.options {
    match option.0 {
      Value(want) => if want.equals(key) { return Some(option.1) }
      Predicate(predicate) =>
        if predicate.accepts(key) {
          return Some(option.1)
        }
      Default => ()
    }
  }
  for option in choose.options {
    if option.0 is Default {
      return Some(option.1)
    }
  }
  choose.otherwise
}

///|
fn step_choose(
  ctx : Ctx,
  input : Array[Traverser],
  choose : Choose,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let branch : Traversal? = match choose.predicate {
      Some(predicate) =>
        if predicate.accepts(traverser.value) {
          choose.then
        } else {
          choose.otherwise
        }
      None =>
        match choose.choice {
          Some(choice) => {
            let produced = run_on(ctx, choice, traverser)
            if produced.is_empty() {
              choose.otherwise
            } else {
              choose.then
            }
          }
          None =>
            match choose.on {
              Some(by) =>
                option_branch(choose, read_by(ctx, by, traverser.value))
              None =>
                if choose.options.is_empty() {
                  choose.then
                } else {
                  option_branch(choose, traverser.value)
                }
            }
        }
    }
    match branch {
      Some(traversal) =>
        for result in run_on(ctx, traversal, traverser) {
          out.push(result)
        }
      None => out.push(traverser)
    }
  }
  out
}
