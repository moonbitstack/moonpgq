---
name: moonpgq
description: Run Gremlin traversals and openCypher read queries over a property graph. Use when a task needs graph traversal, pattern matching, path finding or aggregation over vertices and edges, in MoonBit.
---

# moonpgq

Property-graph queries for MoonBit: a Gremlin engine with its text form, and an
openCypher reader, both over one store contract.

## Install

```bash
moon add moonbitstack/moonpgq
```

The packages are `moonbitstack/moonpgq` (values, the store contract, the step
engine), `moonbitstack/moonpgq/memory` (an in-memory store),
`moonbitstack/moonpgq/gremlin` (the text form) and `moonbitstack/moonpgq/cypher`
(openCypher). Everything is a plain function call: no connection, no server, no
async.

## Build a graph and traverse it

```moonbit
///|
test {
  let graph = @memory.Store::new()
  let asha = graph.add(@moonpgq.Value::Text("asha"), "person", [
    ("name", @moonpgq.Value::Text("asha")),
    ("age", @moonpgq.Value::Int(31L)),
  ])
  let bo = graph.add(@moonpgq.Value::Text("bo"), "person", [
    ("name", @moonpgq.Value::Text("bo")),
    ("age", @moonpgq.Value::Int(45L)),
  ])
  graph.connect(@moonpgq.Value::Text("asha-knows-bo"), "knows", asha.id(), bo.id(), [])
  |> ignore
  let names = @gremlin.run(graph, "g.V().out('knows').values('name')")
  assert_eq(names.map(fn(value) { value.to_text() }), ["bo"])
}
```

## Ask the same question in openCypher

```moonbit
///|
test {
  let graph = @memory.Store::new()
  graph.add(@moonpgq.Value::Text("asha"), "person", [
    ("name", @moonpgq.Value::Text("asha")),
    ("age", @moonpgq.Value::Int(31L)),
  ])
  |> ignore
  let table = @cypher.run(
    graph,
    "MATCH (n:person) RETURN n.name AS name, count(*) AS people",
  )
  assert_eq(table.columns, ["name", "people"])
  assert_eq(table.rows[0].map(fn(value) { value.to_text() }), ["asha", "1"])
}
```

## Query a store of your own

Implement `@moonpgq.Graph` and the engines run unchanged:

```moonbit
///|
fn people(graph : &@moonpgq.Graph) -> Array[String] {
  graph.vertices_with_label("person").map(fn(vertex) {
    vertex.property("name").map(fn(value) { value.to_text() }).unwrap_or("?")
  }).to_array()
}
```

## Things that catch people out

- A traversal step that writes (`addV`, `addE`, `property`, `drop`) changes the
  store as it runs; a query that only reads leaves it untouched.
- `values` and `valueMap` see a property with several values as several values,
  and `valueMap` hands a vertex's values back as a list.
- Aggregation in openCypher groups by every item that is not an aggregate; mix
  `count(*)` with a plain variable and you get one row per distinct value.
- An unbounded variable-length pattern (`*`) stops at eight hops: write `*1..n`
  when the walk should be longer.
- Element equality is by graph and id, so elements from two stores never
  compare equal, even with the same id.
