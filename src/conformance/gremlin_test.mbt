// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn texts(values : Array[@pgq.Value]) -> Array[String] {
  values.map(fn(value) { value.to_text() })
}

///|
fn q(store : &@pgq.Graph, text : String) -> Array[String] raise @pgq.Refused {
  texts(@gremlin.run(store, text))
}

///|
fn sorted(values : Array[String]) -> Array[String] {
  let copy = values.copy()
  copy.sort_by(fn(left, right) { left.compare(right) })
  copy
}

///|
test "counting and filtering" {
  let graph = modern()
  assert_eq(q(graph, "g.V().count()"), ["6"])
  assert_eq(q(graph, "g.E().count()"), ["6"])
  assert_eq(sorted(q(graph, "g.V().hasLabel('person').values('name')")), [
    "josh", "marko", "peter", "vadas",
  ])
  assert_eq(
    q(graph, "g.V().has('name','marko').out('knows').values('name')") |> sorted,
    ["josh", "vadas"],
  )
  assert_eq(q(graph, "g.V().has('age', gt(30)).values('name')") |> sorted, [
    "josh", "peter",
  ])
}

///|
test "ordering, limiting and deduplicating" {
  let graph = modern()
  assert_eq(q(graph, "g.V().values('name').order()"), [
    "josh", "lop", "marko", "peter", "ripple", "vadas",
  ])
  assert_eq(q(graph, "g.V().values('name').order().by(desc).limit(2)"), [
    "vadas", "ripple",
  ])
  assert_eq(q(graph, "g.V().out('created').values('lang').dedup()"), ["java"])
  assert_eq(q(graph, "g.V().out('created').count()"), ["4"])
}

///|
test "paths and labels" {
  let graph = modern()
  assert_eq(
    q(graph, "g.V().has('name','marko').out('knows').path().by('name')")
    |> sorted,
    ["path[marko, josh]", "path[marko, vadas]"],
  )
  assert_eq(
    q(
      graph, "g.V().as('a').out('created').as('b').select('a','b').by('name').count()",
    ),
    ["4"],
  )
  assert_eq(
    q(
      graph, "g.V().has('name','marko').as('a').out('knows').as('b').where('a', neq('b')).values('name')",
    )
    |> sorted,
    ["josh", "vadas"],
  )
}

///|
test "repeat, until and times" {
  let graph = modern()
  assert_eq(
    q(graph, "g.V().has('name','marko').repeat(out()).times(2).values('name')")
    |> sorted,
    ["lop", "ripple"],
  )
  assert_eq(
    q(
      graph, "g.V().has('name','marko').repeat(out()).until(has('name','ripple')).values('name')",
    ),
    ["ripple"],
  )
  assert_eq(
    q(
      graph, "g.V().has('name','marko').repeat(out().simplePath()).times(2).path().count()",
    ),
    ["2"],
  )
}

///|
test "grouping and side effects" {
  let graph = modern()
  let grouped = q(graph, "g.V().groupCount().by(label())")[0]
  assert_eq(grouped, "{person=4, software=2}")
  assert_eq(q(graph, "g.V().aggregate('x').cap('x').unfold().count()"), ["6"])
  assert_eq(q(graph, "g.V().values('age').sum()"), ["123"])
  assert_eq(q(graph, "g.V().values('age').mean()"), ["30.75"])
  assert_eq(q(graph, "g.V().values('age').max()"), ["35"])
  assert_eq(q(graph, "g.V().values('age').fold().count(local)"), ["4"])
  assert_eq(q(graph, "g.V().values('name').fold().unfold().count()"), ["6"])
}

///|
test "branching" {
  let graph = modern()
  assert_eq(
    q(
      graph, "g.V().hasLabel('person').coalesce(values('nickname'), values('name')).count()",
    ),
    ["4"],
  )
  assert_eq(
    q(
      graph, "g.V().hasLabel('person').choose(has('age', gt(30)), values('name'), constant('young')).count()",
    ),
    ["4"],
  )
  assert_eq(
    q(graph, "g.V().union(out('created'), out('knows')).dedup().count()"),
    ["4"],
  )
  assert_eq(
    q(graph, "g.V().has('name','marko').optional(out('none')).count()"),
    ["1"],
  )
}

///|
test "writing: addV, addE, property and drop" {
  let graph = @memory.Store::new()
  assert_eq(
    q(graph, "g.addV('person').property('name','mary').values('name')"),
    ["mary"],
  )
  assert_eq(q(graph, "g.V().count()"), ["1"])
  assert_eq(q(graph, "g.addV('person').property('name','bob').count()"), ["1"])
  assert_eq(
    q(
      graph, "g.V().has('name','mary').addE('knows').to(__.V().has('name','bob')).label()",
    ),
    ["knows"],
  )
  assert_eq(q(graph, "g.E().count()"), ["1"])
  assert_eq(q(graph, "g.V().has('name','bob').drop()"), [])
  assert_eq(q(graph, "g.V().count()"), ["1"])
  assert_eq(q(graph, "g.E().count()"), ["0"])
}

///|
test "value maps" {
  let graph = modern()
  assert_eq(
    q(graph, "g.V().has('name','marko').valueMap('name').unfold()")[0],
    "name=[marko]",
  )
  assert_eq(q(graph, "g.V().has('name','marko').elementMap('name').count()"), [
    "1",
  ])
}

///|
test "a parameter stands for an id" {
  let graph = modern()
  let marko = graph.vertex(@pgq.Value::Text("nope"))
  assert_true(marko is None)
  assert_eq(
    texts(
      @gremlin.run(graph, "g.V(vid).out('knows').values('name')", bindings=[
        ("vid", @pgq.Value::Int(1L)),
      ]),
    )
    |> sorted,
    ["josh", "vadas"],
  )
}

///|
test "a malformed traversal is refused with a position" {
  let graph = modern()
  let failure = Ok(q(graph, "g.V().out(")) catch { error => Err(error) }
  assert_true(failure is Err(_))
}

///|
test "the crew graph repeats a property" {
  let graph = crew()
  assert_eq(q(graph, "g.V().has('name','marko').values('location').count()"), [
    "4",
  ])
  assert_eq(
    q(graph, "g.V().has('name','marko').out('develops').values('name')")
    |> sorted,
    ["gremlin", "tinkergraph"],
  )
}
