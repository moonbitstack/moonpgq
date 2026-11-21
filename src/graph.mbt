// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a query engine needs from a property graph: vertices and edges by id,
/// enumeration, lookup by label and by property value, adjacency in both
/// directions, and the writes that the structural steps perform.
///
/// A store implements this trait and nothing else is needed: the traversal
/// engine, the Gremlin parser and the openCypher executor are written against
/// the trait, so a store that keeps vertices in a file, in another process or
/// behind a key-value contract plugs in without touching this module.
///
/// A read-only store raises `Refused::NotWritable` from the mutating methods.
/// Enumeration order is the store's own; the steps that promise an order sort
/// explicitly.
pub(open) trait Graph {
  ///|
  /// Distinguishes one graph from another, so that two vertices with the same
  /// id in different graphs are not equal.
  fn uid(Self) -> UInt64

  ///|
  fn directed(Self) -> Bool

  ///|
  fn vertex_count(Self) -> Int32

  ///|
  fn edge_count(Self) -> Int32

  ///|
  fn vertex(Self, Value) -> Vertex?

  ///|
  fn edge(Self, Value) -> Edge?

  ///|
  fn vertices(Self) -> Iter[Vertex]

  ///|
  fn edges(Self) -> Iter[Edge]

  ///|
  /// Vertices carrying the label, in the store's order. An empty label string
  /// selects vertices without a label.
  fn vertices_with_label(Self, String) -> Iter[Vertex]

  ///|
  /// Vertices that carry `key` with a value equal to `value`.
  fn vertices_with_property(Self, String, Value) -> Iter[Vertex]

  ///|
  /// Outgoing edges of the vertex, restricted to the given labels when the
  /// array is not empty.
  fn out_edges(Self, Value, Array[String]) -> Iter[Edge]

  ///|
  fn in_edges(Self, Value, Array[String]) -> Iter[Edge]

  ///|
  /// All properties of the vertex, in insertion order. A key may hold several
  /// values.
  fn vertex_properties(Self, Value) -> Array[(String, Array[Value])]

  ///|
  fn edge_properties(Self, Value) -> Array[(String, Array[Value])]

  ///|
  /// Adds a vertex. Without an id the store assigns one.
  fn add_vertex(Self, String, Value?) -> Vertex

  ///|
  /// Adds an edge between two existing vertices. Without an id the store
  /// assigns one.
  fn add_edge(Self, Value, String, Value, Value?) -> Edge

  ///|
  /// Replaces the values of `key` on the element with this one value.
  fn put_property(Self, Element, String, Value) -> Unit

  ///|
  /// Adds a value to a multi-valued property without dropping the others.
  fn append_property(Self, Element, String, Value) -> Unit

  ///|
  fn drop_vertex(Self, Value) -> Unit

  ///|
  fn drop_edge(Self, Value) -> Unit

  ///|
  fn clear(Self) -> Unit
}

///|
/// Every vertex of the graph, or only those carrying the label.
pub fn vertices_of(graph : &Graph, label : String?) -> Iter[Vertex] {
  match label {
    Some(label) => graph.vertices_with_label(label)
    None => graph.vertices()
  }
}

///|
/// The element a value holds, or nothing when the value is not an element.
pub fn element_of(value : Value) -> Element? {
  match value {
    Vertex(vertex) => Some(Element::Vertex(vertex))
    Edge(edge) => Some(Element::Edge(edge))
    _ => None
  }
}

///|
/// The id of the element a value holds, for the steps that index by id.
pub fn id_of(value : Value) -> Value? {
  match value {
    Vertex(vertex) => Some(vertex.id())
    Edge(edge) => Some(edge.id())
    _ => None
  }
}
