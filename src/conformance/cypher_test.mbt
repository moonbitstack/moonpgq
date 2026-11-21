// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A table as lines of text, one per row, so a test reads like the query's
/// answer.
fn lines_of(table : @cypher.Table) -> Array[String] {
  table.rows.map(fn(row) { row.map(fn(value) { value.to_text() }).join(" | ") })
}

///|
test "matching nodes by label and returning a property" {
  let graph = modern()
  let table = @cypher.run(
    graph, "MATCH (n:person) RETURN n.name AS name ORDER BY name",
  )
  assert_eq(table.columns, ["name"])
  assert_eq(lines_of(table), ["josh", "marko", "peter", "vadas"])
}

///|
test "filtering with where" {
  let graph = modern()
  let table = @cypher.run(
    graph, "MATCH (n:person) WHERE n.age > 30 RETURN n.name ORDER BY n.name",
  )
  assert_eq(lines_of(table), ["josh", "peter"])
}

///|
test "following a relationship" {
  let graph = modern()
  let table = @cypher.run(
    graph, "MATCH (a:person)-[:created]->(b:software) RETURN a.name AS who, b.name AS what ORDER BY what, who",
  )
  assert_eq(lines_of(table), [
    "josh | lop", "marko | lop", "peter | lop", "josh | ripple",
  ])
}

///|
test "a variable length path" {
  let graph = modern()
  let table = @cypher.run(
    graph, "MATCH (a {name: 'marko'})-[:knows*1..2]->(b) RETURN DISTINCT b.name AS name ORDER BY name",
  )
  assert_eq(lines_of(table), ["josh", "vadas"])
}

///|
test "optional match keeps the row and fills null" {
  let graph = modern()
  let table = @cypher.run(
    graph, "MATCH (n:software) OPTIONAL MATCH (n)<-[:created]-(p:person) RETURN n.name AS software, count(p) AS people ORDER BY software",
  )
  assert_eq(lines_of(table), ["lop | 3", "ripple | 1"])
}

///|
test "aggregating without a grouping key" {
  let graph = modern()
  let table = @cypher.run(
    graph, "MATCH (n:person) RETURN count(n) AS people, avg(n.age) AS average",
  )
  assert_eq(lines_of(table), ["4 | 30.75"])
}

///|
test "with carries an aggregate into the next clause" {
  let graph = modern()
  let table = @cypher.run(
    graph, "MATCH (p:person)-[:created]->(s) WITH p, count(s) AS made WHERE made > 0 RETURN p.name AS name, made ORDER BY made DESC, name",
  )
  assert_eq(lines_of(table), ["josh | 2", "marko | 1", "peter | 1"])
}

///|
test "unwind walks a list" {
  let graph = modern()
  let table = @cypher.run(
    graph, "UNWIND [1, 2, 3] AS x RETURN x * 2 AS doubled",
  )
  assert_eq(lines_of(table), ["2", "4", "6"])
}

///|
test "skip and limit" {
  let graph = modern()
  let table = @cypher.run(
    graph, "MATCH (n:person) RETURN n.name ORDER BY n.name SKIP 1 LIMIT 2",
  )
  assert_eq(lines_of(table), ["marko", "peter"])
}

///|
test "creating a pattern" {
  let graph = @memory.Store::new()
  let table = @cypher.run(
    graph, "CREATE (a:person {name: 'ada'})-[:knows {since: 1843}]->(b:person {name: 'charles'}) RETURN a.name AS a, b.name AS b",
  )
  assert_eq(lines_of(table), ["ada | charles"])
  assert_eq(graph.vertex_count(), 2)
  assert_eq(graph.edge_count(), 1)
}

///|
test "expressions: arithmetic, strings, case and null" {
  let graph = modern()
  let table = @cypher.run(
    graph, "RETURN 1 + 2 * 3 AS n, 'a' + 'b' AS s, CASE WHEN 1 > 2 THEN 'x' ELSE 'y' END AS c, null IS NULL AS z",
  )
  assert_eq(lines_of(table), ["7 | ab | y | true"])
}

///|
test "a map and list value come back as values" {
  let graph = modern()
  let table = @cypher.run(
    graph, "RETURN [1, 2] AS list, {a: 1} AS map, size([1,2,3]) AS n",
  )
  assert_eq(lines_of(table), ["[1, 2] | {a=1} | 3"])
}

///|
test "the same question in Gremlin and Cypher" {
  let graph = modern()
  let gremlin = @gremlin.run(
    graph, "g.V().hasLabel('person').has('age', gt(30)).values('name').order()",
  )
  let cypher = @cypher.run(
    graph, "MATCH (n:person) WHERE n.age > 30 RETURN n.name ORDER BY n.name",
  )
  assert_eq(
    gremlin.map(fn(value) { value.to_text() }),
    cypher.rows.map(fn(row) { row[0].to_text() }),
  )
}

///|
test "undirected walk returns both directions" {
  let graph = modern()
  let table = @cypher.run(
    graph, "MATCH (a)-[:knows]-(b) RETURN a.name AS a, b.name AS b",
  )
  println("rows: " + lines_of(table).join(" / "))
  assert_eq(table.rows.length(), 4)
}

///|
test "a path variable and its length" {
  let graph = @memory.Store::new()
  let table = @cypher.run(
    graph, "CREATE (a:person {name: 'ada'})-[:knows {since: 1843}]->(b:person {name: 'charles'}) RETURN a.name AS a",
  )
  assert_eq(table.rows.length(), 1)
  let walked = @cypher.run(
    graph, "MATCH p = (a)-[r:knows]->(b) RETURN length(p) AS hops, r.since AS since",
  )
  assert_eq(walked.rows[0].map(fn(value) { value.to_text() }), ["1", "1843"])
}
