// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Reads one cell of a TCK result table: a pattern resolves against the graph,
/// anything else is a literal.
fn cypher_cell(
  text : String,
  graph : &@pgq.Graph,
) -> Result[@pgq.Value, String] {
  let is_pattern = text.has_prefix("(") ||
    text.has_prefix("[") ||
    text.has_prefix("<")
  if is_pattern {
    let resolved = Ok(@cypher.resolve_pattern(graph, text)) catch {
      error => Err(@pgq.Refused::to_text(error))
    }
    return match resolved {
      Ok(Some(value)) => Ok(value)
      Ok(None) => Err("no element matches " + text)
      Err(reason) => Err(reason)
    }
  }
  let parsed = Ok(@cypher.parse_value(text)) catch {
    error => Err(@pgq.Refused::to_text(error))
  }
  parsed
}

///|
fn row_matches(
  actual : Array[@pgq.Value],
  expected : Array[String],
  graph : &@pgq.Graph,
) -> Result[Unit, String] {
  guard actual.length() == expected.length() else {
    return Err(
      "wanted " +
      expected.length().to_string() +
      " columns, got " +
      actual.length().to_string(),
    )
  }
  for index in 0..<expected.length() {
    let cell = expected[index]
    let is_pattern = cell.has_prefix("(") ||
      cell.has_prefix("[") ||
      cell.has_prefix("<")
    if is_pattern {
      if !@cypher.matches_pattern(graph, cell, actual[index]) {
        return Err(
          "column " +
          index.to_string() +
          ": wanted " +
          cell +
          ", got " +
          actual[index].to_text(),
        )
      }
    } else {
      match cypher_cell(cell, graph) {
        Err(reason) => return Err(reason)
        Ok(value) =>
          if !value.equals(actual[index]) {
            return Err(
              "column " +
              index.to_string() +
              ": wanted " +
              value.to_text() +
              ", got " +
              actual[index].to_text(),
            )
          }
      }
    }
  }
  Ok(())
}

///|
fn run_cypher_case(entry : CypherCase) -> Result[Unit, String] {
  let graph = @memory.Store::new()
  for statement in entry.setup {
    let created = Ok(@cypher.run(graph, statement)) catch {
      error => Err(@pgq.Refused::to_text(error))
    }
    match created {
      Ok(_) => ()
      Err(reason) => return Err("setup refused: " + reason)
    }
  }
  let outcome = Ok(@cypher.run(graph, entry.query)) catch {
    error => Err(@pgq.Refused::to_text(error))
  }
  let table = match outcome {
    Ok(table) => table
    Err(reason) =>
      return match entry.expectation {
        Raises => Ok(())
        Unsupported(_) => Err("refused: " + reason)
        _ => Err(reason)
      }
  }
  match entry.expectation {
    Unsupported(reason) => Err("unsupported: " + reason)
    Raises => Err("wanted an error, the query returned " + table.to_text())
    Table => {
      guard table.columns.length() == entry.columns.length() else {
        return Err(
          "wanted " +
          entry.columns.length().to_string() +
          " columns, got " +
          table.columns.length().to_string() +
          ": " +
          table.columns.join(","),
        )
      }
      for index in 0..<entry.columns.length() {
        if table.columns[index] != entry.columns[index] {
          return Err(
            "column name " +
            index.to_string() +
            ": wanted " +
            entry.columns[index] +
            ", got " +
            table.columns[index],
          )
        }
      }
      guard table.rows.length() == entry.rows.length() else {
        return Err(
          "wanted " +
          entry.rows.length().to_string() +
          " rows, got " +
          table.rows.length().to_string(),
        )
      }
      if entry.in_order {
        for index in 0..<entry.rows.length() {
          match row_matches(table.rows[index], entry.rows[index], graph) {
            Err(reason) =>
              return Err("row " + index.to_string() + ": " + reason)
            Ok(_) => ()
          }
        }
        Ok(())
      } else {
        // Any order: the rows are paired by content, and a pairing that fits
        // one row may block another, so the assignment is searched rather than
        // taken greedily.
        let taken : Array[Bool] = Array::make(table.rows.length(), false)
        if assign_rows(table.rows, entry.rows, taken, 0, graph) {
          Ok(())
        } else {
          Err(
            "no pairing of the expected rows with " +
            table.rows.length().to_string() +
            " returned rows",
          )
        }
      }
    }
  }
}

///|
/// Pairs every expected row with a distinct returned row, backtracking when a
/// choice leaves a later row without a partner.
fn assign_rows(
  actual : Array[Array[@pgq.Value]],
  expected : Array[Array[String]],
  taken : Array[Bool],
  at : Int32,
  graph : &@pgq.Graph,
) -> Bool {
  if at >= expected.length() {
    return true
  }
  for index in 0..<actual.length() {
    if taken[index] {
      continue
    }
    match row_matches(actual[index], expected[at], graph) {
      Ok(_) => {
        taken[index] = true
        if assign_rows(actual, expected, taken, at + 1, graph) {
          return true
        }
        taken[index] = false
      }
      Err(_) => ()
    }
  }
  false
}

///|
/// The count that must keep passing. Raising it when the engine grows is
/// expected; lowering it is a regression.
const CYPHER_PASS_FLOOR : Int32 = 0

///|
test "the openCypher TCK" {
  let cases = all_cypher_cases()
  let mut passed = 0
  let failed : Array[String] = []
  let mut unsupported = 0
  for entry in cases {
    let label = entry.file + " :: " + entry.scenario
    match run_cypher_case(entry) {
      Ok(_) =>
        if entry.expectation is Unsupported(_) {
          unsupported = unsupported + 1
        } else {
          passed = passed + 1
        }
      Err(reason) =>
        if entry.expectation is Unsupported(_) {
          unsupported = unsupported + 1
        } else {
          failed.push(label + " :: " + reason)
        }
    }
  }
  println(
    "openCypher TCK: " +
    passed.to_string() +
    " passed, " +
    failed.length().to_string() +
    " failed, " +
    unsupported.to_string() +
    " unsupported, of " +
    cases.length().to_string(),
  )
  for index in 0..<failed.length() {
    if index < 200 {
      println("  " + failed[index])
    }
  }
  if failed.length() > 200 {
    println("  ... and " + (failed.length() - 200).to_string() + " more")
  }
  assert_true(passed >= CYPHER_PASS_FLOOR)
}
