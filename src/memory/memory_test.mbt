// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A small graph for the tests of this package: two people, one software, and
/// the edges between them.
fn sample() -> @memory.Store {
  let store = @memory.Store::new()
  let marko = store.add(@pgq.Value::Text("marko"), "person", [
    ("name", @pgq.Value::Text("marko")),
    ("age", @pgq.Value::Int(29L)),
  ])
  let vadas = store.add(@pgq.Value::Text("vadas"), "person", [
    ("name", @pgq.Value::Text("vadas")),
    ("age", @pgq.Value::Int(27L)),
  ])
  let lop = store.add(@pgq.Value::Text("lop"), "software", [
    ("name", @pgq.Value::Text("lop")),
    ("lang", @pgq.Value::Text("java")),
  ])
  store.connect(
    @pgq.Value::Text("marko-knows->vadas"),
    "knows",
    marko.id(),
    vadas.id(),
    [("weight", @pgq.Value::Double(0.5))],
  )
  |> ignore
  store.connect(
    @pgq.Value::Text("marko-created->lop"),
    "created",
    marko.id(),
    lop.id(),
    [("weight", @pgq.Value::Double(0.4))],
  )
  |> ignore
  store
}

///|
test "vertices keep their label, id and properties" {
  let store = sample()
  assert_eq(store.vertex_count(), 3)
  assert_eq(store.edge_count(), 2)
  let marko = store.vertex(@pgq.Value::Text("marko")).unwrap()
  assert_eq(marko.label(), "person")
  assert_eq(marko.values("name").length(), 1)
  assert_eq(marko.values("name")[0].to_text(), "marko")
  assert_eq(marko.property("age").unwrap().to_text(), "29")
}

///|
test "adjacency follows the direction of the edge" {
  let store = sample()
  let out = store.out_edges(@pgq.Value::Text("marko"), ["created"]).to_array()
  assert_eq(out.length(), 1)
  assert_eq(out[0].label(), "created")
  let back = store.in_edges(@pgq.Value::Text("lop"), []).to_array()
  assert_eq(back.length(), 1)
  assert_eq(back[0].out_id().to_text(), "marko")
}

///|
test "removing a vertex removes the edges that touch it" {
  let store = sample()
  store.drop_vertex(@pgq.Value::Text("lop"))
  assert_eq(store.vertex_count(), 2)
  assert_eq(store.edge_count(), 1)
  assert_true(store.vertex(@pgq.Value::Text("lop")) is None)
}

///|
test "a property with several values keeps them in order" {
  let store = @memory.Store::open()
  let marko = store.add(@pgq.Value::Text("marko"), "person", [])
  store.add_property(
    @pgq.Element::Vertex(marko),
    "location",
    @pgq.Value::Text("san diego"),
  )
  store.add_property(
    @pgq.Element::Vertex(marko),
    "location",
    @pgq.Value::Text("santa cruz"),
  )
  assert_eq(marko.values("location").length(), 2)
  assert_eq(marko.values("location")[1].to_text(), "santa cruz")
}

///|
test "putting a property replaces the values of that key" {
  let store = @memory.Store::open()
  let marko = store.add(@pgq.Value::Text("marko"), "person", [
    ("age", @pgq.Value::Int(29L)),
  ])
  store.put_property(@pgq.Element::Vertex(marko), "age", @pgq.Value::Int(30L))
  assert_eq(marko.values("age").length(), 1)
  assert_eq(marko.values("age")[0].to_text(), "30")
}

///|
test "lookups by label and by property value" {
  let store = sample()
  assert_eq(store.vertices_with_label("person").count(), 2)
  assert_eq(
    store.vertices_with_property("name", @pgq.Value::Text("lop")).count(),
    1,
  )
}

///|
test "assigned ids do not collide with explicit ones" {
  let store = @memory.Store::open()
  store.add(@pgq.Value::Int(1L), "person", []) |> ignore
  let second = @pgq.Graph::add_vertex(store, "person", None)
  assert_true(!second.id().equals(@pgq.Value::Int(1L)))
}
