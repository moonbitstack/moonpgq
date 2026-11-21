// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Parses a traversal and runs it against a graph: the one call a caller needs
/// when the query arrives as text.
pub fn run(
  graph : &@pgq.Graph,
  text : StringView,
  bindings~ : Array[(String, @pgq.Value)] = [],
) -> Array[@pgq.Value] raise @pgq.Refused {
  let plan = parse(text, bindings~)
  @pgq.values_of(graph, plan)
}

///|
/// Parses a traversal and returns the plan without running it, which is what a
/// caller wants to inspect, store or translate.
pub fn plan(
  text : StringView,
  bindings~ : Array[(String, @pgq.Value)] = [],
) -> @pgq.Traversal raise @pgq.Refused {
  parse(text, bindings~)
}
