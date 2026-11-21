// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A graph of the people in a small studio and what they worked on.
fn studio() -> @memory.Store {
  let graph = @memory.Store::new()
  let ada = graph.add(@pgq.Value::Text("ada"), "person", [
    ("name", @pgq.Value::Text("ada")),
    ("role", @pgq.Value::Text("engineer")),
  ])
  let bo = graph.add(@pgq.Value::Text("bo"), "person", [
    ("name", @pgq.Value::Text("bo")),
    ("role", @pgq.Value::Text("engineer")),
  ])
  let cy = graph.add(@pgq.Value::Text("cy"), "person", [
    ("name", @pgq.Value::Text("cy")),
    ("role", @pgq.Value::Text("designer")),
  ])
  let atlas = graph.add(@pgq.Value::Text("atlas"), "project", [
    ("name", @pgq.Value::Text("atlas")),
    ("year", @pgq.Value::Int(2024L)),
  ])
  let beacon = graph.add(@pgq.Value::Text("beacon"), "project", [
    ("name", @pgq.Value::Text("beacon")),
    ("year", @pgq.Value::Int(2025L)),
  ])
  graph.connect(@pgq.Value::Text("e1"), "works_on", ada.id(), atlas.id(), [])
  |> ignore
  graph.connect(@pgq.Value::Text("e2"), "works_on", bo.id(), atlas.id(), [])
  |> ignore
  graph.connect(@pgq.Value::Text("e3"), "works_on", bo.id(), beacon.id(), [])
  |> ignore
  graph.connect(@pgq.Value::Text("e4"), "works_on", cy.id(), beacon.id(), [])
  |> ignore
  graph
}

///|
fn show(label : String, values : Array[@pgq.Value]) -> Unit {
  println(label + ": " + values.map(fn(value) { value.to_text() }).join(", "))
}

///|
fn main raise @pgq.Refused {
  let graph = studio()
  show(
    "every project",
    @gremlin.run(graph, "g.V().hasLabel('project').values('name').order()"),
  )
  show(
    "who worked on atlas",
    @gremlin.run(
      graph, "g.V().has('name','atlas').in('works_on').values('name').order()",
    ),
  )
  show(
    "how many projects each person touched",
    @gremlin.run(
      graph, "g.V().hasLabel('person').groupCount().by('name').select(values)",
    ),
  )
  show(
    "who shares a project with ada",
    @gremlin.run(
      graph, "g.V().has('name','ada').out('works_on').in('works_on').values('name').dedup().order()",
    ),
  )
}
