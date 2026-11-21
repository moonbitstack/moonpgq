// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The modern graph the Gremlin feature suite is written against.
fn modern() -> @memory.Store {
  let store = @memory.Store::new()
  let marko = store.add(@pgq.Value::Int(1L), "person", [
    ("name", @pgq.Value::Text("marko")),
    ("age", @pgq.Value::Int(29L)),
  ])
  let vadas = store.add(@pgq.Value::Int(2L), "person", [
    ("name", @pgq.Value::Text("vadas")),
    ("age", @pgq.Value::Int(27L)),
  ])
  let lop = store.add(@pgq.Value::Int(3L), "software", [
    ("name", @pgq.Value::Text("lop")),
    ("lang", @pgq.Value::Text("java")),
  ])
  let josh = store.add(@pgq.Value::Int(4L), "person", [
    ("name", @pgq.Value::Text("josh")),
    ("age", @pgq.Value::Int(32L)),
  ])
  let ripple = store.add(@pgq.Value::Int(5L), "software", [
    ("name", @pgq.Value::Text("ripple")),
    ("lang", @pgq.Value::Text("java")),
  ])
  let peter = store.add(@pgq.Value::Int(6L), "person", [
    ("name", @pgq.Value::Text("peter")),
    ("age", @pgq.Value::Int(35L)),
  ])
  store.connect(@pgq.Value::Int(7L), "knows", marko.id(), vadas.id(), [
    ("weight", @pgq.Value::Double(0.5)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(8L), "knows", marko.id(), josh.id(), [
    ("weight", @pgq.Value::Double(1.0)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(9L), "created", marko.id(), lop.id(), [
    ("weight", @pgq.Value::Double(0.4)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(10L), "created", josh.id(), ripple.id(), [
    ("weight", @pgq.Value::Double(1.0)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(11L), "created", josh.id(), lop.id(), [
    ("weight", @pgq.Value::Double(0.4)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(12L), "created", peter.id(), lop.id(), [
    ("weight", @pgq.Value::Double(0.2)),
  ])
  |> ignore
  store
}

///|
/// The crew graph: people and the software they develop and use, with
/// multi-valued locations.
fn crew() -> @memory.Store {
  let store = @memory.Store::open(multi_valued=true)
  let marko = store.add(@pgq.Value::Int(1L), "person", [
    ("name", @pgq.Value::Text("marko")),
  ])
  let stephen = store.add(@pgq.Value::Int(7L), "person", [
    ("name", @pgq.Value::Text("stephen")),
  ])
  let matthias = store.add(@pgq.Value::Int(8L), "person", [
    ("name", @pgq.Value::Text("matthias")),
  ])
  let daniel = store.add(@pgq.Value::Int(9L), "person", [
    ("name", @pgq.Value::Text("daniel")),
  ])
  let gremlin = store.add(@pgq.Value::Int(10L), "software", [
    ("name", @pgq.Value::Text("gremlin")),
  ])
  let tinkergraph = store.add(@pgq.Value::Int(11L), "software", [
    ("name", @pgq.Value::Text("tinkergraph")),
  ])
  for location in ["san diego", "santa cruz", "brussels", "santa fe"] {
    store.add_property(
      @pgq.Element::Vertex(marko),
      "location",
      @pgq.Value::Text(location),
    )
  }
  for location in ["centreville", "dulles", "purcellville"] {
    store.add_property(
      @pgq.Element::Vertex(stephen),
      "location",
      @pgq.Value::Text(location),
    )
  }
  for location in ["bremen", "baltimore", "oakland", "seattle"] {
    store.add_property(
      @pgq.Element::Vertex(matthias),
      "location",
      @pgq.Value::Text(location),
    )
  }
  for location in ["spremberg", "kaiserslautern", "aachen"] {
    store.add_property(
      @pgq.Element::Vertex(daniel),
      "location",
      @pgq.Value::Text(location),
    )
  }
  store.connect(@pgq.Value::Int(13L), "develops", marko.id(), gremlin.id(), [
    ("since", @pgq.Value::Int(2009L)),
  ])
  |> ignore
  store.connect(
    @pgq.Value::Int(14L),
    "develops",
    marko.id(),
    tinkergraph.id(),
    [("since", @pgq.Value::Int(2010L))],
  )
  |> ignore
  store.connect(@pgq.Value::Int(15L), "uses", marko.id(), gremlin.id(), [
    ("skill", @pgq.Value::Int(4L)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(16L), "uses", marko.id(), tinkergraph.id(), [
    ("skill", @pgq.Value::Int(5L)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(17L), "develops", stephen.id(), gremlin.id(), [
    ("since", @pgq.Value::Int(2010L)),
  ])
  |> ignore
  store.connect(
    @pgq.Value::Int(18L),
    "develops",
    stephen.id(),
    tinkergraph.id(),
    [("since", @pgq.Value::Int(2011L))],
  )
  |> ignore
  store.connect(@pgq.Value::Int(19L), "uses", stephen.id(), gremlin.id(), [
    ("skill", @pgq.Value::Int(5L)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(20L), "uses", stephen.id(), tinkergraph.id(), [
    ("skill", @pgq.Value::Int(4L)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(21L), "develops", matthias.id(), gremlin.id(), [
    ("since", @pgq.Value::Int(2012L)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(22L), "uses", matthias.id(), gremlin.id(), [
    ("skill", @pgq.Value::Int(3L)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(23L), "uses", matthias.id(), tinkergraph.id(), [
    ("skill", @pgq.Value::Int(3L)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(24L), "uses", daniel.id(), gremlin.id(), [
    ("skill", @pgq.Value::Int(5L)),
  ])
  |> ignore
  store.connect(@pgq.Value::Int(25L), "uses", daniel.id(), tinkergraph.id(), [
    ("skill", @pgq.Value::Int(3L)),
  ])
  |> ignore
  store.connect(
    @pgq.Value::Int(26L),
    "traverses",
    gremlin.id(),
    tinkergraph.id(),
    [],
  )
  |> ignore
  store
}
