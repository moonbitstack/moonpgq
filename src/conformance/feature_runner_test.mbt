// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Builds the graph a case names. Each case gets its own, since a scenario may
/// write.
fn fixture_for(name : String) -> Fixture {
  if name == "modern" {
    Fixture::of(modern())
  } else if name == "crew" {
    Fixture::of(crew())
  } else {
    Fixture::of(@memory.Store::new())
  }
}

///|
/// Runs one scenario and reports the first way it differed.
fn evaluate_case(case : FeatureCase) -> Result[Unit, String] {
  let fixture = fixture_for(case.graph)
  let bindings : Array[(String, @pgq.Value)] = []
  for parameter in case.parameters {
    let parsed = Ok(parse_cell(parameter.1, fixture)) catch {
      error => Err(@pgq.Refused::to_text(error))
    }
    match parsed {
      Ok(value) => bindings.push((parameter.0, value))
      Err(reason) => return Err("parameter " + parameter.0 + ": " + reason)
    }
  }
  let plan = Ok(@gremlin.parse(case.query, bindings~)) catch {
    error => Err(@pgq.Refused::to_text(error))
  }
  let outcome = match plan {
    Ok(plan) =>
      Ok(@pgq.run(fixture.store, plan)) catch {
        error => Err(@pgq.Refused::to_text(error))
      }
    Err(reason) => Err(reason)
  }
  if case.expectation is Raises {
    return match outcome {
      Ok(_) => Err("wanted an error, the traversal returned")
      Err(_) => Ok(())
    }
  }
  let outcome = match outcome {
    Ok(outcome) => outcome
    Err(reason) => return Err(reason)
  }
  match case.expectation {
    Unsupported(reason) => Err("unsupported: " + reason)
    Empty =>
      if outcome.values.is_empty() {
        Ok(())
      } else {
        Err("wanted no results, got " + show(outcome.values))
      }
    Count(want) =>
      if outcome.values.length().to_int64() == want {
        Ok(())
      } else {
        Err(
          "wanted count " +
          want.to_string() +
          ", got " +
          outcome.values.length().to_string() +
          " " +
          show(outcome.values),
        )
      }
    Ordered(want) => {
      let expected = parse_cells(want, fixture)
      match expected {
        Err(reason) => Err(reason)
        Ok(expected) =>
          if same_list(outcome.values, expected) {
            Ok(())
          } else {
            Err("wanted " + show(expected) + ", got " + show(outcome.values))
          }
      }
    }
    Unordered(want) => {
      let expected = parse_cells(want, fixture)
      match expected {
        Err(reason) => Err(reason)
        Ok(expected) =>
          if same_multiset(outcome.values, expected) {
            Ok(())
          } else {
            Err("wanted " + show(expected) + ", got " + show(outcome.values))
          }
      }
    }
    AnyOf(want) => {
      let expected = parse_cells(want, fixture)
      match expected {
        Err(reason) => Err(reason)
        Ok(expected) =>
          if outcome.values.all(fn(value) {
              expected.any(fn(option) { same(value, option) })
            }) {
            Ok(())
          } else {
            Err(
              "wanted one of " +
              show(expected) +
              ", got " +
              show(outcome.values),
            )
          }
      }
    }
    GraphCount(want, query) => {
      let counted = Ok(@gremlin.run(fixture.store, query)) catch {
        error => Err(@pgq.Refused::to_text(error))
      }
      match counted {
        Err(reason) => Err(reason)
        Ok(values) =>
          if values.length().to_int64() == want {
            Ok(())
          } else {
            Err(
              "wanted the graph to hold " +
              want.to_string() +
              ", got " +
              values.length().to_string(),
            )
          }
      }
    }
    Raises => Ok(())
  }
}

///|
fn parse_cells(
  cells : Array[String],
  fixture : Fixture,
) -> Result[Array[@pgq.Value], String] {
  let values : Array[@pgq.Value] = []
  for cell in cells {
    let parsed = Ok(parse_cell(cell, fixture)) catch {
      error => Err(@pgq.Refused::to_text(error))
    }
    match parsed {
      Ok(value) => values.push(value)
      Err(reason) => return Err("cell " + cell + ": " + reason)
    }
  }
  Ok(values)
}

///|
fn same_list(actual : Array[@pgq.Value], expected : Array[@pgq.Value]) -> Bool {
  guard actual.length() == expected.length() else { return false }
  for index in 0..<actual.length() {
    guard same(actual[index], expected[index]) else { return false }
  }
  true
}

///|
fn same_multiset(
  actual : Array[@pgq.Value],
  expected : Array[@pgq.Value],
) -> Bool {
  guard actual.length() == expected.length() else { return false }
  let taken : Array[Bool] = Array::make(actual.length(), false)
  for want in expected {
    let mut found = false
    for index in 0..<actual.length() {
      if !taken[index] && same(actual[index], want) {
        taken[index] = true
        found = true
        break
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
fn show(values : Array[@pgq.Value]) -> String {
  "[" + values.map(fn(value) { value.to_text() }).join(", ") + "]"
}

///|
/// The count that must keep passing. Raising it when the engine grows is
/// expected; lowering it is a regression.
const GREMLIN_PASS_FLOOR : Int32 = 0

///|
test "the Gremlin feature suite" {
  let cases = all_feature_cases()
  let mut passed = 0
  let failed : Array[String] = []
  let mut unsupported = 0
  for case in cases {
    let label = case.file + " :: " + case.scenario
    match evaluate_case(case) {
      Ok(_) =>
        if case.expectation is Unsupported(_) {
          unsupported = unsupported + 1
        } else {
          passed = passed + 1
        }
      Err(reason) =>
        if case.expectation is Unsupported(_) {
          unsupported = unsupported + 1
        } else {
          failed.push(label + " :: " + reason)
        }
    }
  }
  println(
    "Gremlin feature suite: " +
    passed.to_string() +
    " passed, " +
    failed.length().to_string() +
    " failed, " +
    unsupported.to_string() +
    " unsupported, of " +
    cases.length().to_string(),
  )
  for index in 0..<failed.length() {
    if index < 700 {
      println("  " + failed[index])
    }
  }
  if failed.length() > 700 {
    println("  ... and " + (failed.length() - 700).to_string() + " more")
  }
  assert_true(passed >= GREMLIN_PASS_FLOOR)
}
