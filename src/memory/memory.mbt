// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// An in-memory property graph whose topology is a `moongraph` graph.
// Apache TinkerPop's in-memory graph is the shape this follows:
// https://tinkerpop.apache.org/docs/current/reference/#tinkergraph-gremlin

///|
/// One vertex as the store keeps it: its id, its label and its properties.
pub(all) struct VertexRecord {
  id : @pgq.Value
  label : String
  properties : Array[(String, Array[@pgq.Value])]
}

///|
/// One edge as the store keeps it.
pub(all) struct EdgeRecord {
  id : @pgq.Value
  label : String
  out_v : @pgq.Value
  in_v : @pgq.Value
  properties : Array[(String, Array[@pgq.Value])]
}

///|
/// A property graph in memory. Topology, adjacency and node numbering come from
/// `moongraph`; labels, properties and multi-valued keys live here because a
/// property graph needs them and a plain graph does not.
pub struct Store {
  graph : @moongraph.Graph[Int32, Int32]
  uid : UInt64
  vertices : Array[VertexRecord?]
  edges : Array[EdgeRecord?]
  vertex_slots : Map[String, Int32]
  edge_slots : Map[String, Int32]
  /// The moongraph node number of each slot. Node numbers shift when a vertex
  /// is removed, so this is rebuilt after a removal.
  mut slot_to_dense : Array[Int32?]
  mut next_vertex_id : Int64
  mut next_edge_id : Int64
  multi_valued : Bool
}

///|
let next_uid : Ref[UInt64] = Ref(1UL)

///|
/// An empty directed property graph.
pub fn Store::new() -> Store {
  Store::open()
}

///|
/// An empty property graph. `multi_valued` makes `property()` append instead of
/// replace, which is what a graph with list cardinality wants.
pub fn Store::open(
  directed~ : Bool = true,
  multi_valued~ : Bool = false,
) -> Store {
  let uid = next_uid.val
  next_uid.val = uid + 1UL
  {
    graph: @moongraph.Graph::new(directed~),
    uid,
    vertices: [],
    edges: [],
    vertex_slots: Map([]),
    edge_slots: Map([]),
    slot_to_dense: [],
    next_vertex_id: 1L,
    next_edge_id: 1L,
    multi_valued,
  }
}

///|
/// The key an id is stored under. The tag keeps the integer 1 and the string
/// "1" apart, since both are legal ids and both print the same.
fn id_key(id : @pgq.Value) -> String {
  match id {
    Text(text) => "s:" + text
    Int(number) => "i:" + number.to_string()
    Double(number) => "d:" + @pgq.format_double(number)
    _ => "x:" + id.to_text()
  }
}

///|
fn Store::slot_of_vertex(self : Store, id : @pgq.Value) -> Int32? {
  self.vertex_slots.get(id_key(id))
}

///|
fn Store::slot_of_edge(self : Store, id : @pgq.Value) -> Int32? {
  self.edge_slots.get(id_key(id))
}

///|
fn Store::vertex_record(self : Store, id : @pgq.Value) -> VertexRecord? {
  match self.slot_of_vertex(id) {
    Some(slot) =>
      match self.vertices.get(slot) {
        Some(Some(record)) => Some(record)
        _ => None
      }
    None => None
  }
}

///|
fn Store::edge_record(self : Store, id : @pgq.Value) -> EdgeRecord? {
  match self.slot_of_edge(id) {
    Some(slot) =>
      match self.edges.get(slot) {
        Some(Some(record)) => Some(record)
        _ => None
      }
    None => None
  }
}

///|
/// The moongraph node number of a vertex, which adjacency asks for.
fn Store::dense_of(self : Store, id : @pgq.Value) -> Int32? {
  match self.slot_of_vertex(id) {
    None => None
    Some(slot) =>
      match self.slot_to_dense.get(slot) {
        Some(Some(node)) => Some(node)
        _ => None
      }
  }
}

///|
fn Store::element_of_vertex(self : Store, record : VertexRecord) -> @pgq.Vertex {
  @pgq.Vertex::new(self, record.id, record.label)
}

///|
fn Store::element_of_edge(self : Store, record : EdgeRecord) -> @pgq.Edge {
  @pgq.Edge::new(self, record.id, record.label, record.out_v, record.in_v)
}

///|
fn label_matches(labels : Array[String], label : String) -> Bool {
  labels.is_empty() || labels.contains(label)
}

///|
fn Store::rebuild_dense(self : Store) -> Unit {
  let dense : Array[Int32?] = Array::make(self.vertices.length(), None)
  self.graph
  .nodes()
  .each(fn(node) {
    let slot = self.graph.node_data(node)
    if slot >= 0 && slot < dense.length() {
      dense[slot] = Some(node)
    }
  })
  self.slot_to_dense = dense
}

///|
/// Allocates an id that no vertex or edge uses yet.
fn Store::fresh_id(self : Store, for_vertex : Bool) -> @pgq.Value {
  let mut candidate = if for_vertex {
    self.next_vertex_id
  } else {
    self.next_edge_id
  }
  while true {
    let value = @pgq.Value::Int(candidate)
    if self.slot_of_vertex(value) is None && self.slot_of_edge(value) is None {
      if for_vertex {
        self.next_vertex_id = candidate + 1L
      } else {
        self.next_edge_id = candidate + 1L
      }
      return value
    }
    candidate = candidate + 1L
  }
  @pgq.Value::Nil
}

///|
pub impl @pgq.Graph for Store with fn uid(self) {
  self.uid
}

///|
pub impl @pgq.Graph for Store with fn directed(self) {
  self.graph.directed()
}

///|
pub impl @pgq.Graph for Store with fn vertex_count(self) {
  self.vertices.iter().filter(fn(record) { record is Some(_) }).count()
}

///|
pub impl @pgq.Graph for Store with fn edge_count(self) {
  self.edges.iter().filter(fn(record) { record is Some(_) }).count()
}

///|
pub impl @pgq.Graph for Store with fn vertex(self, id) {
  match self.vertex_record(id) {
    Some(record) => Some(self.element_of_vertex(record))
    None => None
  }
}

///|
pub impl @pgq.Graph for Store with fn edge(self, id) {
  match self.edge_record(id) {
    Some(record) => Some(self.element_of_edge(record))
    None => None
  }
}

///|
pub impl @pgq.Graph for Store with fn vertices(self) {
  // The snapshot is taken now: a traversal may add a vertex while this
  // iterator runs, and a moving bound would never end.
  let out : Array[@pgq.Vertex] = []
  for record in self.vertices {
    match record {
      Some(record) => out.push(self.element_of_vertex(record))
      None => ()
    }
  }
  out.iter()
}

///|
pub impl @pgq.Graph for Store with fn edges(self) {
  let out : Array[@pgq.Edge] = []
  for record in self.edges {
    match record {
      Some(record) => out.push(self.element_of_edge(record))
      None => ()
    }
  }
  out.iter()
}

///|
pub impl @pgq.Graph for Store with fn vertices_with_label(self, label) {
  @pgq.Graph::vertices(self).filter(fn(vertex) { vertex.label() == label })
}

///|
pub impl @pgq.Graph for Store with fn vertices_with_property(self, key, value) {
  @pgq.Graph::vertices(self).filter(fn(vertex) {
    vertex.values(key).any(fn(actual) { actual.equals(value) })
  })
}

///|
pub impl @pgq.Graph for Store with fn out_edges(self, id, labels) {
  let store = self
  match self.dense_of(id) {
    None => Iter::empty()
    Some(node) =>
      self.graph
      .incident(node)
      .iter()
      .filter(fn(edge_number) {
        let (from, to) = store.graph.endpoints(edge_number)
        let reaches = if store.graph.directed() {
          from == node
        } else {
          from == node || to == node
        }
        if !reaches {
          return false
        }
        let slot = store.graph.edge_data(edge_number)
        match store.edges.get(slot) {
          Some(Some(record)) => label_matches(labels, record.label)
          _ => false
        }
      })
      .map(fn(edge_number) {
        let slot = store.graph.edge_data(edge_number)
        let record = store.edges[slot].unwrap()
        store.element_of_edge(record)
      })
  }
}

///|
pub impl @pgq.Graph for Store with fn in_edges(self, id, labels) {
  let store = self
  match self.dense_of(id) {
    None => Iter::empty()
    Some(node) => {
      let incident = if self.graph.directed() {
        self.graph.in_incident(node)
      } else {
        self.graph.incident(node)
      }
      incident
      .iter()
      .filter(fn(edge_number) {
        let (from, to) = store.graph.endpoints(edge_number)
        let reaches = if store.graph.directed() {
          to == node
        } else {
          from == node || to == node
        }
        if !reaches {
          return false
        }
        let slot = store.graph.edge_data(edge_number)
        match store.edges.get(slot) {
          Some(Some(record)) => label_matches(labels, record.label)
          _ => false
        }
      })
      .map(fn(edge_number) {
        let slot = store.graph.edge_data(edge_number)
        let record = store.edges[slot].unwrap()
        store.element_of_edge(record)
      })
    }
  }
}

///|
pub impl @pgq.Graph for Store with fn vertex_properties(self, id) {
  match self.vertex_record(id) {
    Some(record) => record.properties
    None => []
  }
}

///|
pub impl @pgq.Graph for Store with fn edge_properties(self, id) {
  match self.edge_record(id) {
    Some(record) => record.properties
    None => []
  }
}

///|
pub impl @pgq.Graph for Store with fn add_vertex(self, label, id) {
  let chosen = match id {
    Some(id) => id
    None => self.fresh_id(true)
  }
  let record : VertexRecord = { id: chosen, label, properties: [], }
  let slot = self.vertices.length()
  self.vertices.push(Some(record))
  self.vertex_slots[id_key(chosen)] = slot
  let node = self.graph.add_node(slot)
  self.slot_to_dense.push(Some(node))
  self.element_of_vertex(record)
}

///|
pub impl @pgq.Graph for Store with fn add_edge(self, out_v, label, in_v, id) {
  let chosen = match id {
    Some(id) => id
    None => self.fresh_id(false)
  }
  let from = self.dense_of(out_v)
  let to = self.dense_of(in_v)
  let record : EdgeRecord = { id: chosen, label, out_v, in_v, properties: [], }
  let slot = self.edges.length()
  self.edges.push(Some(record))
  self.edge_slots[id_key(chosen)] = slot
  match (from, to) {
    (Some(from), Some(to)) => {
      let number = self.graph.add_edge(from, to, slot)
      // @pgq.Edge numbers never shift, so the record keeps its own slot; the
      // moongraph edge is only there for adjacency.
      ignore(number)
    }
    _ => ()
  }
  self.element_of_edge(record)
}

///|
pub impl @pgq.Graph for Store with fn put_property(self, element, key, value) {
  match element {
    @pgq.Vertex(vertex) =>
      match self.vertex_slots.get(id_key(vertex.id())) {
        Some(slot) =>
          match self.vertices.get(slot) {
            Some(Some(record)) => {
              let updated : VertexRecord = {
                id: record.id,
                label: record.label,
                properties: put_entry(record.properties, key, [value]),
              }
              self.vertices[slot] = Some(updated)
            }
            _ => ()
          }
        None => ()
      }
    @pgq.Edge(edge) =>
      match self.edge_slots.get(id_key(edge.id())) {
        Some(slot) =>
          match self.edges.get(slot) {
            Some(Some(record)) => {
              let updated : EdgeRecord = {
                id: record.id,
                label: record.label,
                out_v: record.out_v,
                in_v: record.in_v,
                properties: put_entry(record.properties, key, [value]),
              }
              self.edges[slot] = Some(updated)
            }
            _ => ()
          }
        None => ()
      }
  }
}

///|
pub impl @pgq.Graph for Store with fn append_property(self, element, key, value) {
  match element {
    @pgq.Vertex(vertex) =>
      match self.vertex_slots.get(id_key(vertex.id())) {
        Some(slot) =>
          match self.vertices.get(slot) {
            Some(Some(record)) => {
              let existing = @pgq.find_property(record.properties, key).unwrap_or([],
              )
              let updated : VertexRecord = {
                id: record.id,
                label: record.label,
                properties: put_entry(
                  record.properties,
                  key,
                  existing + [value],
                ),
              }
              self.vertices[slot] = Some(updated)
            }
            _ => ()
          }
        None => ()
      }
    @pgq.Edge(edge) =>
      match self.edge_slots.get(id_key(edge.id())) {
        Some(slot) =>
          match self.edges.get(slot) {
            Some(Some(record)) => {
              let existing = @pgq.find_property(record.properties, key).unwrap_or([],
              )
              let updated : EdgeRecord = {
                id: record.id,
                label: record.label,
                out_v: record.out_v,
                in_v: record.in_v,
                properties: put_entry(
                  record.properties,
                  key,
                  existing + [value],
                ),
              }
              self.edges[slot] = Some(updated)
            }
            _ => ()
          }
        None => ()
      }
  }
}

///|
/// Replaces a key's values, keeping the position the key already had.
fn put_entry(
  properties : Array[(String, Array[@pgq.Value])],
  key : String,
  values : Array[@pgq.Value],
) -> Array[(String, Array[@pgq.Value])] {
  let out : Array[(String, Array[@pgq.Value])] = []
  let mut replaced = false
  for entry in properties {
    if entry.0 == key {
      out.push((key, values))
      replaced = true
    } else {
      out.push(entry)
    }
  }
  if !replaced {
    out.push((key, values))
  }
  out
}

///|
pub impl @pgq.Graph for Store with fn drop_vertex(self, id) {
  match self.slot_of_vertex(id) {
    None => ()
    Some(slot) => {
      self.vertices[slot] = None
      self.vertex_slots.remove(id_key(id))
      match self.dense_of(id) {
        Some(node) => self.graph.remove_node(node)
        None => ()
      }
      // The records keep their slots, so only the numbering has to follow.
      if slot < self.slot_to_dense.length() {
        self.slot_to_dense[slot] = None
      }
      self.rebuild_dense()
      self.prune_edges()
    }
  }
}

///|
/// Drops the edges whose ends are gone: `drop_vertex` removes them from the
/// topology, and the records have to follow.
fn Store::prune_edges(self : Store) -> Unit {
  for slot in 0..<self.edges.length() {
    match self.edges[slot] {
      Some(record) =>
        if self.slot_of_vertex(record.out_v) is None ||
          self.slot_of_vertex(record.in_v) is None {
          self.edges[slot] = None
          self.edge_slots.remove(id_key(record.id))
        }
      None => ()
    }
  }
}

///|
pub impl @pgq.Graph for Store with fn drop_edge(self, id) {
  match self.slot_of_edge(id) {
    None => ()
    Some(slot) => {
      self.edges[slot] = None
      self.edge_slots.remove(id_key(id))
      self.graph
      .edges()
      .each(fn(number) {
        if self.graph.edge_data(number) == slot {
          self.graph.remove_edge(number)
        }
      })
    }
  }
}

///|
pub impl @pgq.Graph for Store with fn clear(self) {
  self.graph.clear()
  self.vertices.clear()
  self.edges.clear()
  self.vertex_slots.clear()
  self.edge_slots.clear()
  self.slot_to_dense.clear()
}

///|
/// Adds a vertex and sets its properties in one call, which is how a fixture
/// reads.
pub fn Store::add(
  self : Store,
  id : @pgq.Value,
  label : String,
  properties : Array[(String, @pgq.Value)],
) -> @pgq.Vertex {
  let vertex = @pgq.Graph::add_vertex(self, label, Some(id))
  for property in properties {
    @pgq.Graph::put_property(
      self,
      @pgq.Element::Vertex(vertex),
      property.0,
      property.1,
    )
  }
  vertex
}

///|
/// Adds an edge and sets its properties in one call.
pub fn Store::connect(
  self : Store,
  id : @pgq.Value,
  label : String,
  out_v : @pgq.Value,
  in_v : @pgq.Value,
  properties : Array[(String, @pgq.Value)],
) -> @pgq.Edge {
  let edge = @pgq.Graph::add_edge(self, out_v, label, in_v, Some(id))
  for property in properties {
    @pgq.Graph::put_property(
      self,
      @pgq.Element::Edge(edge),
      property.0,
      property.1,
    )
  }
  edge
}

///|
/// Adds a value to a multi-valued property, as `property()` with list
/// cardinality does.
pub fn Store::add_property(
  self : Store,
  element : @pgq.Element,
  key : String,
  value : @pgq.Value,
) -> Unit {
  @pgq.Graph::append_property(self, element, key, value)
}

///|
/// Promotes the contract's methods onto `Store`, so a caller with a concrete
/// store writes `store.out_edges(...)` instead of `@pgq.Graph::out_edges(store, ...)`.
pub extend Store with @pgq.Graph::{
  uid,
  directed,
  vertex_count,
  edge_count,
  vertex,
  edge,
  vertices,
  edges,
  vertices_with_label,
  vertices_with_property,
  out_edges,
  in_edges,
  vertex_properties,
  edge_properties,
  add_vertex,
  add_edge,
  put_property,
  append_property,
  drop_vertex,
  drop_edge,
  clear,
}
