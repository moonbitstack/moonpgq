// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A vertex of a property graph.
///
/// The element is a handle: it carries the graph it belongs to and its id, and
/// asks the graph for label and properties. A traversal can therefore move
/// elements through steps without copying them, and a write through one step is
/// visible to the next.
pub struct Vertex {
  graph : &Graph
  id : Value
  label : String
}

///|
pub fn Vertex::new(graph : &Graph, id : Value, label : String) -> Vertex {
  { graph, id, label, }
}

///|
pub fn Vertex::id(self : Vertex) -> Value {
  self.id
}

///|
pub fn Vertex::label(self : Vertex) -> String {
  self.label
}

///|
/// The graph this vertex belongs to.
pub fn Vertex::graph(self : Vertex) -> &Graph {
  self.graph
}

///|
/// Every property, in insertion order, with all values of a multi-valued key.
pub fn Vertex::properties(self : Vertex) -> Array[(String, Array[Value])] {
  self.graph.vertex_properties(self.id)
}

///|
pub fn Vertex::values(self : Vertex, key : String) -> Array[Value] {
  find_property(self.properties(), key).unwrap_or([])
}

///|
pub fn Vertex::property(self : Vertex, key : String) -> Value? {
  self.values(key).get(0)
}

///|
pub fn Vertex::equals(self : Vertex, other : Vertex) -> Bool {
  self.graph.uid() == other.graph.uid() && self.id.equals(other.id)
}

///|
pub fn Vertex::key(self : Vertex) -> String {
  self.id.to_text()
}

///|
pub fn Vertex::to_text(self : Vertex) -> String {
  "v[" + self.id.to_text() + "]"
}

///|
pub impl Show for Vertex with fn to_string(self) {
  self.to_text()
}

///|
/// An edge of a property graph, with the ids of the vertices at its ends.
pub struct Edge {
  graph : &Graph
  id : Value
  label : String
  out_v : Value
  in_v : Value
}

///|
pub fn Edge::new(
  graph : &Graph,
  id : Value,
  label : String,
  out_v : Value,
  in_v : Value,
) -> Edge {
  { graph, id, label, out_v, in_v, }
}

///|
pub fn Edge::id(self : Edge) -> Value {
  self.id
}

///|
pub fn Edge::label(self : Edge) -> String {
  self.label
}

///|
pub fn Edge::graph(self : Edge) -> &Graph {
  self.graph
}

///|
/// The id of the vertex the edge starts at.
pub fn Edge::out_id(self : Edge) -> Value {
  self.out_v
}

///|
/// The id of the vertex the edge ends at.
pub fn Edge::in_id(self : Edge) -> Value {
  self.in_v
}

///|
pub fn Edge::out_vertex(self : Edge) -> Vertex? {
  self.graph.vertex(self.out_v)
}

///|
pub fn Edge::in_vertex(self : Edge) -> Vertex? {
  self.graph.vertex(self.in_v)
}

///|
pub fn Edge::properties(self : Edge) -> Array[(String, Array[Value])] {
  self.graph.edge_properties(self.id)
}

///|
pub fn Edge::values(self : Edge, key : String) -> Array[Value] {
  find_property(self.properties(), key).unwrap_or([])
}

///|
pub fn Edge::property(self : Edge, key : String) -> Value? {
  self.values(key).get(0)
}

///|
pub fn Edge::equals(self : Edge, other : Edge) -> Bool {
  self.graph.uid() == other.graph.uid() && self.id.equals(other.id)
}

///|
pub fn Edge::key(self : Edge) -> String {
  self.id.to_text()
}

///|
pub fn Edge::to_text(self : Edge) -> String {
  "e[" + self.id.to_text() + "]"
}

///|
pub impl Show for Edge with fn to_string(self) {
  self.to_text()
}

///|
/// A vertex or an edge, for the steps that accept either.
pub(all) enum Element {
  Vertex(Vertex)
  Edge(Edge)
}

///|
pub fn Element::id(self : Element) -> Value {
  match self {
    Vertex(vertex) => vertex.id()
    Edge(edge) => edge.id()
  }
}

///|
pub fn Element::label(self : Element) -> String {
  match self {
    Vertex(vertex) => vertex.label()
    Edge(edge) => edge.label()
  }
}

///|
pub fn Element::properties(self : Element) -> Array[(String, Array[Value])] {
  match self {
    Vertex(vertex) => vertex.properties()
    Edge(edge) => edge.properties()
  }
}

///|
pub fn Element::property(self : Element, key : String) -> Value? {
  match self {
    Vertex(vertex) => vertex.property(key)
    Edge(edge) => edge.property(key)
  }
}

///|
pub fn Element::to_text(self : Element) -> String {
  match self {
    Vertex(vertex) => vertex.to_text()
    Edge(edge) => edge.to_text()
  }
}

///|
pub fn Element::to_value(self : Element) -> Value {
  match self {
    Vertex(vertex) => Value::Vertex(vertex)
    Edge(edge) => Value::Edge(edge)
  }
}

///|
pub fn Element::key(self : Element) -> String {
  match self {
    Vertex(vertex) => "v:" + vertex.key()
    Edge(edge) => "e:" + edge.key()
  }
}

///|
/// One property of an element: the key and one of its values.
pub struct Property {
  key : String
  value : Value
}

///|
pub fn Property::new(key : String, value : Value) -> Property {
  { key, value, }
}

///|
pub fn Property::key(self : Property) -> String {
  self.key
}

///|
pub fn Property::value(self : Property) -> Value {
  self.value
}

///|
pub fn Property::to_text(self : Property) -> String {
  "p[" + self.key + "->" + self.value.to_text() + "]"
}

///|
pub impl Show for Property with fn to_string(self) {
  self.to_text()
}

///|
/// The walk a traverser took, one value per step that changed it.
pub struct Path {
  objects : Array[Value]
}

///|
pub fn Path::new(objects : Array[Value]) -> Path {
  { objects, }
}

///|
pub fn Path::objects(self : Path) -> Array[Value] {
  self.objects
}

///|
pub fn Path::at(self : Path, index : Int32) -> Value? {
  self.objects.get(index)
}

///|
pub fn Path::size(self : Path) -> Int32 {
  self.objects.length()
}

///|
pub fn Path::to_text(self : Path) -> String {
  "path[" + self.objects.map(fn(object) { object.to_text() }).join(", ") + "]"
}

///|
pub impl Show for Path with fn to_string(self) {
  self.to_text()
}

///|
pub fn Value::element(self : Value) -> Element? {
  match self {
    Vertex(vertex) => Some(Element::Vertex(vertex))
    Edge(edge) => Some(Element::Edge(edge))
    _ => None
  }
}
