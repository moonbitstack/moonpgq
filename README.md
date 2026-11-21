# moonpgq

Property-graph query languages for MoonBit. One store contract, two languages
over it: a Gremlin traversal engine with its text form, and an openCypher
reader with `MATCH`, `OPTIONAL MATCH`, `WHERE`, `WITH`, `UNWIND`, `RETURN` and
aggregation.

Nothing here needs a database. A graph of a few thousand vertices lives in
memory, and a store of your own plugs in by implementing one trait.

```moonbit
///|
test {
  let graph = @memory.Store::new()
  let alice = graph.add(@moonpgq.Value::Text("alice"), "person", [
    ("name", @moonpgq.Value::Text("alice")),
    ("age", @moonpgq.Value::Int(34L)),
  ])
  let bob = graph.add(@moonpgq.Value::Text("bob"), "person", [
    ("name", @moonpgq.Value::Text("bob")),
    ("age", @moonpgq.Value::Int(28L)),
  ])
  graph.connect(@moonpgq.Value::Text("alice-knows-bob"), "knows", alice.id(), bob.id(), [])
  |> ignore
  let names = @gremlin.run(graph, "g.V().hasLabel('person').values('name').order()")
  assert_eq(names.map(fn(value) { value.to_text() }), ["alice", "bob"])
}
```

The same graph, the same question, in openCypher:

```moonbit
///|
test {
  let graph = @memory.Store::new()
  graph.add(@moonpgq.Value::Text("alice"), "person", [
    ("name", @moonpgq.Value::Text("alice")),
    ("age", @moonpgq.Value::Int(34L)),
  ])
  |> ignore
  graph.add(@moonpgq.Value::Text("bob"), "person", [
    ("name", @moonpgq.Value::Text("bob")),
    ("age", @moonpgq.Value::Int(28L)),
  ])
  |> ignore
  let table = @cypher.run(
    graph,
    "MATCH (n:person) WHERE n.age > 30 RETURN n.name AS name",
  )
  assert_eq(table.columns, ["name"])
  assert_eq(table.rows.map(fn(row) { row[0].to_text() }), ["alice"])
}
```

## The store contract

`@moonpgq.Graph` is what a query engine needs from a graph: vertices and edges
by id, enumeration, lookup by label and by property value, adjacency in both
directions, and the writes that the structural steps perform. The traversal
engine, the Gremlin parser and the Cypher executor are written against the
trait, so a store backed by a file, another process or a key-value contract
plugs in without touching this module.

```moonbit
///|
fn count_people(graph : &@moonpgq.Graph) -> Int {
  graph.vertices_with_label("person").count()
}
```

The in-memory store is `@memory.Store`. Topology, adjacency and node numbering
come from `moongraph`; labels, properties and multi-valued keys live beside it,
because a property graph needs them and a plain graph does not.

```moonbit
///|
test {
  let graph = @memory.Store::open(multi_valued=true)
  let marko = graph.add(@moonpgq.Value::Text("marko"), "person", [])
  graph.add_property(@moonpgq.Element::Vertex(marko), "location", @moonpgq.Value::Text("san diego"))
  graph.add_property(@moonpgq.Element::Vertex(marko), "location", @moonpgq.Value::Text("santa fe"))
  assert_eq(marko.values("location").length(), 2)
}
```

## Gremlin

A traversal is the plan. The text form and the embedded form produce the same
sequence of steps, so a query can be parsed, inspected, stored and run later.

```moonbit
///|
test {
  let graph = @memory.Store::new()
  let a = graph.add(@moonpgq.Value::Int(1L), "person", [("name", @moonpgq.Value::Text("a"))])
  let b = graph.add(@moonpgq.Value::Int(2L), "person", [("name", @moonpgq.Value::Text("b"))])
  graph.connect(@moonpgq.Value::Int(3L), "knows", a.id(), b.id(), []) |> ignore
  let plan = @gremlin.parse("g.V().out('knows').values('name')")
  assert_eq(plan.to_text(), "V().out(knows).values(name)")
  let results = @moonpgq.values_of(graph, plan)
  assert_eq(results.map(fn(value) { value.to_text() }), ["b"])
}
```

The steps are the ones the traversal language defines: `V`, `E`, `out`, `in`,
`both`, `outE`, `inV`, `bothE`, `otherV`, `has`, `hasLabel`, `hasId`, `hasKey`,
`hasValue`, `hasNot`, `is`, `where`, `filter`, `not`, `and`, `or`, `values`,
`valueMap`, `elementMap`, `propertyMap`, `properties`, `key`, `value`, `label`,
`id`, `as`, `select`, `path`, `simplePath`, `cyclicPath`, `order`, `limit`,
`skip`, `range`, `tail`, `dedup`, `sample`, `count`, `sum`, `mean`, `max`, `min`,
`fold`, `unfold`, `group`, `groupCount`, `aggregate`, `store`, `cap`,
`sideEffect`, `project`, `inject`, `map`, `flatMap`, `local`, `coalesce`,
`optional`, `union`, `choose`, `branch`, `repeat` with `until`/`emit`/`times`,
`loops`, `identity`, `constant`, `drop`, `property`, `addV` and `addE`.

Predicates come in both spellings, `has('age', gt(30))` and
`has('age', P.gt(30))`, and `by()` modulates the step before it:

```moonbit
///|
test {
  let graph = @memory.Store::new()
  let a = graph.add(@moonpgq.Value::Int(1L), "person", [
    ("name", @moonpgq.Value::Text("a")),
    ("age", @moonpgq.Value::Int(30L)),
  ])
  let b = graph.add(@moonpgq.Value::Int(2L), "person", [
    ("name", @moonpgq.Value::Text("b")),
    ("age", @moonpgq.Value::Int(40L)),
  ])
  graph.connect(@moonpgq.Value::Int(3L), "knows", a.id(), b.id(), []) |> ignore
  let names = @gremlin.run(
    graph,
    "g.V().has('age', P.gt(20)).order().by('age', Order.desc).values('name')",
  )
  assert_eq(names.map(fn(value) { value.to_text() }), ["b", "a"])
}
```

A scenario that binds ids passes them by name:

```moonbit
///|
test {
  let graph = @memory.Store::new()
  graph.add(@moonpgq.Value::Int(7L), "person", [("name", @moonpgq.Value::Text("a"))])
  |> ignore
  let names = @gremlin.run(graph, "g.V(vid).values('name')", bindings=[
    ("vid", @moonpgq.Value::Int(7L)),
  ])
  assert_eq(names.map(fn(value) { value.to_text() }), ["a"])
}
```

## openCypher

`MATCH` with variable-length paths, `OPTIONAL MATCH`, `WHERE`, `WITH` with
aggregation, `UNWIND`, `RETURN` with `DISTINCT`, `ORDER BY`, `SKIP` and `LIMIT`.
`CREATE` is there too, so a fixture can be loaded before the read.

```moonbit
///|
test {
  let graph = @memory.Store::new()
  let table = @cypher.run(
    graph,
    "CREATE (a:person {name: 'ada'})-[:knows {since: 1843}]->(b:person {name: 'charles'}) " +
    "RETURN a.name AS a, b.name AS b",
  )
  assert_eq(table.rows.length(), 1)
  let walked = @cypher.run(
    graph,
    "MATCH p = (a)-[r:knows]->(b) RETURN length(p) AS hops, r.since AS since",
  )
  assert_eq(walked.rows[0].map(fn(value) { value.to_text() }), ["1", "1843"])
}
```

Aggregation groups by the items that are not aggregates:

```moonbit
///|
test {
  let graph = @memory.Store::new()
  for name in ["ada", "charles", "grace"] {
    graph.add(@moonpgq.Value::Text(name), "person", [
      ("name", @moonpgq.Value::Text(name)),
      ("city", @moonpgq.Value::Text("london")),
    ])
    |> ignore
  }
  let table = @cypher.run(
    graph,
    "MATCH (n:person) RETURN n.city AS city, count(*) AS people",
  )
  assert_eq(table.columns, ["city", "people"])
  assert_eq(table.rows[0].map(fn(value) { value.to_text() }), ["london", "3"])
}
```

## Packages

| Package | What it holds |
|:--|:--|
| `moonbitstack/moonpgq` | values, elements, the store contract, the step plan and the engine |
| `moonbitstack/moonpgq/memory` | the in-memory store, on a `moongraph` graph |
| `moonbitstack/moonpgq/gremlin` | the text form of Gremlin |
| `moonbitstack/moonpgq/cypher` | openCypher read queries |

## Conformance

Two official suites run against the engine, replayed from the files they ship
in. The counts below come from `moon test -p moonbitstack/moonpgq/conformance`;
the vendored files are under `scripts/conformance/` and the case data beside
them is generated by `scripts/gen_gremlin_cases.py` and
`scripts/gen_cypher_cases.py`.

**Gremlin feature suite.** 1213 scenarios from 60 feature files of the Apache
TinkerPop suite. 555 pass, 484 return a different result, 174 are refused.

Reasons a scenario is refused or fails, in order of size:

| Reason | Count |
|:--|--:|
| a predicate whose operand is a traversal, e.g. `has('name', eq(constant('x')))` | 54 |
| `withSack`, `sack`, `withSideEffect` and the like | 30 |
| steps outside the read core: `match`, `math`, `concat`, `asString`, `element`, `labels`, `branch`, `combine`, `mergeV`, `mergeE`, `call` | 90 |
| results of steps that produce `VertexProperty` values, which the value model does not have | 40 |
| `tree()`, `subgraph()`, IO steps and the `with()` options they need | 30 |
| `repeat()` with a body that walks both ways grows past the frontier limit and is refused | 12 |
| a graph other than the modern, the crew or an empty one (the grateful, zoo, sink and delivery graphs) | 57 |
| the rest: ordering of ties, side-effect ordering, multi-property cardinality | 375 |

**openCypher TCK.** 287 scenarios from 25 feature files of the openCypher
compliance suite. 156 pass, 115 return a different result, 16 are refused.

| Reason | Count |
|:--|--:|
| multi-label patterns: the model gives an element one label | 22 |
| production rules not implemented: `SET`, `DELETE`, `MERGE`, `remove`, `union` | 0 (not vendored) |
| compile-time error checks (the query is refused, but the cases check the message) | 12 |
| path comparison and relationship uniqueness inside one pattern | 30 |
| the rest: expression typing and null handling in edge cases | 51 |

Both suites pass the count they must not fall below, so a regression fails the
build.
