// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One value on its way through the traversal, with the labels it collected and
/// the walk it took.
pub(all) struct Traverser {
  value : Value
  path : Array[Value]
  /// Name, position in the path, value: `select()` reads the value, `path()`
  /// with `from()` and `to()` reads the position.
  labels : Array[(String, Int32, Value)]
  loops : Int32
}

///|
pub fn Traverser::value(self : Traverser) -> Value {
  self.value
}

///|
fn start_traverser(value : Value) -> Traverser {
  { value, path: [value], labels: [], loops: 0, }
}

///|
/// A step that produced a new value extends the walk.
fn advance(traverser : Traverser, value : Value) -> Traverser {
  {
    value,
    path: traverser.path + [value],
    labels: traverser.labels,
    loops: traverser.loops,
  }
}

///|
fn relabel(traverser : Traverser, name : String) -> Traverser {
  let at = traverser.path.length() - 1
  {
    value: traverser.value,
    path: traverser.path,
    labels: traverser.labels + [(name, at, traverser.value)],
    loops: traverser.loops,
  }
}

///|
/// The state one query runs in: the graph, the side effects steps have written,
/// and the scratch a repeat needs.
pub struct Ctx {
  graph : &Graph
  effects : Array[(String, Array[Value])]
}

///|
fn Ctx::new(graph : &Graph) -> Ctx {
  { graph, effects: [], }
}

///|
fn Ctx::push_effect(self : Ctx, key : String, value : Value) -> Unit {
  match array_find(self.effects, fn(entry) { entry.0 == key }) {
    Some(entry) => entry.1.push(value)
    None => self.effects.push((key, [value]))
  }
}

///|
fn Ctx::effect(self : Ctx, key : String) -> Array[Value] {
  array_find(self.effects, fn(entry) { entry.0 == key })
  .map(fn(entry) { entry.1 })
  .unwrap_or([])
}

///|
/// What a query returns: the results and the side effects that were not capped.
pub(all) struct Outcome {
  values : Array[Value]
  side_effects : Array[(String, Value)]
}

///|
/// Runs a plan against a graph.
pub fn run(graph : &Graph, traversal : Traversal) -> Outcome raise Refused {
  let ctx = Ctx::new(graph)
  let results = run_steps(ctx, [], traversal, 0)
  let effects : Array[(String, Value)] = []
  for entry in ctx.effects {
    for value in entry.1 {
      effects.push((entry.0, value))
    }
  }
  {
    values: results.map(fn(traverser) { traverser.value }),
    side_effects: effects,
  }
}

///|
/// Runs a plan and returns only its results.
pub fn values_of(
  graph : &Graph,
  traversal : Traversal,
) -> Array[Value] raise Refused {
  run(graph, traversal).values
}

///|
/// The executor contract: a component that runs a plan against a graph.
pub(open) trait Executor {
  fn execute(Self, &Graph, Traversal) -> Outcome raise Refused
}

///|
/// The executor this module ships: the step machine in `engine.mbt` and the
/// files beside it.
pub(all) struct Standard {}

///|
pub impl Executor for Standard with fn execute(_self, graph, traversal) {
  run(graph, traversal)
}

///|
/// Feeds the traversers through the remaining steps.
fn run_steps(
  ctx : Ctx,
  input : Array[Traverser],
  traversal : Traversal,
  at : Int32,
) -> Array[Traverser] raise Refused {
  let mut current = input
  let mut index = at
  while index < traversal.steps.length() {
    current = apply_step(ctx, current, traversal.steps[index])
    index = index + 1
  }
  current
}

///|
/// Runs a nested traversal on one traverser, keeping its labels and its walk.
fn run_on(
  ctx : Ctx,
  inner : Traversal,
  traverser : Traverser,
) -> Array[Traverser] raise Refused {
  run_steps(ctx, [traverser], inner, 0)
}

///|
fn apply_step(
  ctx : Ctx,
  input : Array[Traverser],
  step : Step,
) -> Array[Traverser] raise Refused {
  match step {
    Vertices(ids) => step_vertices(ctx, ids)
    Edges(ids) => step_edges(ctx, ids)
    AddVertex(label, properties) =>
      step_add_vertex(ctx, input, label, properties)
    AddEdge(label, properties, from, to) =>
      step_add_edge(ctx, input, label, properties, from, to)
    Out(labels) => step_adjacent(ctx, input, labels, Direction::Out)
    In(labels) => step_adjacent(ctx, input, labels, Direction::In)
    Both(labels) => step_adjacent(ctx, input, labels, Direction::Both)
    OutEdges(labels) => step_incident(ctx, input, labels, Direction::Out)
    InEdges(labels) => step_incident(ctx, input, labels, Direction::In)
    BothEdges(labels) => step_incident(ctx, input, labels, Direction::Both)
    OutVertex => step_incident_vertex(ctx, input, Direction::Out)
    InVertex => step_incident_vertex(ctx, input, Direction::In)
    BothVertices => step_incident_vertex(ctx, input, Direction::Both)
    OtherVertex => step_other_vertex(ctx, input)
    HasLabel(labels) => filter_has_label(input, labels)
    HasId(ids) => filter_has_id(input, ids)
    HasKey(keys) => filter_has_key(input, keys)
    HasValue(values) => filter_has_value(input, values)
    Has(has) => filter_has(input, has)
    HasNot(keys) => filter_has_not(input, keys)
    Values(keys) => step_values(ctx, input, keys)
    ValueMap(keys, bys, with_tokens) =>
      step_value_map(ctx, input, keys, bys, with_tokens)
    ElementMap(keys, bys) => step_element_map(ctx, input, keys, bys)
    PropertyMap(keys, bys) => step_property_map(ctx, input, keys, bys)
    Properties(keys, bys) => step_properties(ctx, input, keys, bys)
    ElementKey => step_element_key(ctx, input)
    ElementValue => step_element_value(ctx, input)
    ElementLabel => step_element_label(ctx, input)
    ElementId => step_element_id(ctx, input)
    Count(scope) => step_count(ctx, input, scope)
    Sum(scope, bys) => step_sum(ctx, input, scope, bys)
    Mean(scope, bys) => step_mean(ctx, input, scope, bys)
    Max(scope, bys) => step_extreme(ctx, input, scope, bys, true)
    Min(scope, bys) => step_extreme(ctx, input, scope, bys, false)
    Fold(scope) => step_fold(input, scope)
    Unfold => step_unfold(ctx, input)
    Limit(limit, scope) => step_range(ctx, input, 0L, limit, scope)
    Skip(offset, scope) => step_range(ctx, input, offset, -1L, scope)
    Range(low, high, scope) => step_range(ctx, input, low, high, scope)
    Tail(limit, scope) => step_tail(ctx, input, limit, scope)
    Dedup(labels, bys, scope) => step_dedup(ctx, input, labels, bys, scope)
    Order(scope, comparators) => step_order(ctx, input, scope, comparators)
    Group(key, comparators) => step_group(ctx, input, key, comparators)
    GroupCount(key, by) => step_group_count(ctx, input, key, by)
    Cap(keys) => step_cap(ctx, keys)
    PathStep(bys, from, to) => step_path(ctx, input, bys, from, to)
    SimplePath => filter_simple_path(input, true)
    CyclicPath => filter_simple_path(input, false)
    Select(keys, bys, pop) => step_select(ctx, input, keys, bys, pop)
    WhereStep(kind) => filter_where(ctx, input, kind)
    FilterStep(inner) => filter_by_traversal(ctx, input, inner)
    NotStep(inner) => filter_not(ctx, input, inner)
    AndStep(inners) => filter_and(ctx, input, inners)
    OrStep(inners) => filter_or(ctx, input, inners)
    Is(predicate) => filter_is(input, predicate)
    Constant(value) => input.map(fn(traverser) { advance(traverser, value) })
    MapStep(inner, _scope) => step_map(ctx, input, inner)
    FlatMapStep(inner) => step_flat_map(ctx, input, inner)
    LocalStep(inner) => step_local(ctx, input, inner)
    RepeatStep(repeat) => step_repeat(ctx, input, repeat)
    Coalesce(inners) => step_coalesce(ctx, input, inners)
    OptionalStep(inner) => step_optional(ctx, input, inner)
    Union(inners) => step_union(ctx, input, inners)
    ChooseStep(choose) => step_choose(ctx, input, choose)
    Inject(values) => step_inject(values, input)
    Aggregate(key, scope, by) => step_collect(ctx, input, key, scope, by)
    Store(key, scope, by) => step_collect(ctx, input, key, scope, by)
    SideEffect(inner) => step_side_effect(ctx, input, inner)
    Project(keys, bys) => step_project(ctx, input, keys, bys)
    Sample(amount, scope) => step_sample(ctx, input, amount, scope)
    Loops =>
      input.map(fn(traverser) {
        advance(traverser, Value::Int(traverser.loops.to_int64()))
      })
    Drop => step_drop(ctx, input)
    PropertyStep(key, value, cardinality) =>
      step_property(ctx, input, key, value, cardinality)
    As(name) => input.map(fn(traverser) { relabel(traverser, name) })
    Identity => input
  }
}

///|
/// Which way an adjacency step walks.
#derive(Eq)
pub(all) enum Direction {
  Out
  In
  Both
}

///|
fn step_vertices(ctx : Ctx, ids : Array[Value]) -> Array[Traverser] {
  if ids.is_empty() {
    ctx.graph
    .vertices()
    .map(fn(vertex) { start_traverser(Value::Vertex(vertex)) })
    .to_array()
  } else {
    let found : Array[Traverser] = []
    for id in ids {
      match ctx.graph.vertex(id) {
        Some(vertex) => found.push(start_traverser(Value::Vertex(vertex)))
        None => ()
      }
    }
    found
  }
}

///|
fn step_edges(ctx : Ctx, ids : Array[Value]) -> Array[Traverser] {
  if ids.is_empty() {
    ctx.graph
    .edges()
    .map(fn(edge) { start_traverser(Value::Edge(edge)) })
    .to_array()
  } else {
    let found : Array[Traverser] = []
    for id in ids {
      match ctx.graph.edge(id) {
        Some(edge) => found.push(start_traverser(Value::Edge(edge)))
        None => ()
      }
    }
    found
  }
}

///|
fn step_adjacent(
  ctx : Ctx,
  input : Array[Traverser],
  labels : Array[String],
  direction : Direction,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let vertex = require_vertex("out()/in()/both()", traverser.value)
    let edges : Array[Edge] = []
    if direction == Direction::Out || direction == Direction::Both {
      ctx.graph
      .out_edges(vertex.id(), labels)
      .each(fn(edge) { edges.push(edge) })
    }
    if direction == Direction::In || direction == Direction::Both {
      ctx.graph
      .in_edges(vertex.id(), labels)
      .each(fn(edge) { edges.push(edge) })
    }
    for edge in edges {
      let step_out = direction == Direction::Out ||
        (direction == Direction::Both && edge.out_id().equals(vertex.id()))
      let next = if step_out { edge.in_vertex() } else { edge.out_vertex() }
      match next {
        Some(next) => out.push(advance(traverser, Value::Vertex(next)))
        None => ()
      }
    }
  }
  out
}

///|
fn step_incident(
  ctx : Ctx,
  input : Array[Traverser],
  labels : Array[String],
  direction : Direction,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let vertex = require_vertex("outE()/inE()/bothE()", traverser.value)
    if direction == Direction::Out || direction == Direction::Both {
      ctx.graph
      .out_edges(vertex.id(), labels)
      .each(fn(edge) { out.push(advance(traverser, Value::Edge(edge))) })
    }
    if direction == Direction::In || direction == Direction::Both {
      ctx.graph
      .in_edges(vertex.id(), labels)
      .each(fn(edge) { out.push(advance(traverser, Value::Edge(edge))) })
    }
  }
  out
}

///|
fn step_incident_vertex(
  _ctx : Ctx,
  input : Array[Traverser],
  direction : Direction,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let edge = require_edge("outV()/inV()/bothV()", traverser.value)
    if direction == Direction::Out || direction == Direction::Both {
      match edge.out_vertex() {
        Some(vertex) => out.push(advance(traverser, Value::Vertex(vertex)))
        None => ()
      }
    }
    if direction == Direction::In || direction == Direction::Both {
      match edge.in_vertex() {
        Some(vertex) => out.push(advance(traverser, Value::Vertex(vertex)))
        None => ()
      }
    }
  }
  out
}

///|
fn step_other_vertex(
  _ctx : Ctx,
  input : Array[Traverser],
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let edge = require_edge("otherV()", traverser.value)
    let previous = traverser.path
      .rev_iter()
      .find_first(fn(value) {
        match value {
          Vertex(_) => true
          _ => false
        }
      })
    let next = match previous {
      Some(Vertex(vertex)) =>
        if vertex.id().equals(edge.out_id()) {
          edge.in_vertex()
        } else {
          edge.out_vertex()
        }
      _ => edge.out_vertex()
    }
    match next {
      Some(vertex) => out.push(advance(traverser, Value::Vertex(vertex)))
      None => ()
    }
  }
  out
}

///|
fn step_add_vertex(
  ctx : Ctx,
  input : Array[Traverser],
  label : String,
  properties : Array[(String, Value)],
) -> Array[Traverser] {
  let created = ctx.graph.add_vertex(label, None)
  for property in properties {
    ctx.graph.put_property(Element::Vertex(created), property.0, property.1)
  }
  let value = Value::Vertex(created)
  if input.is_empty() {
    [start_traverser(value)]
  } else {
    input.map(fn(traverser) { advance(traverser, value) })
  }
}

///|
fn step_add_edge(
  ctx : Ctx,
  input : Array[Traverser],
  label : String,
  properties : Array[(String, Value)],
  from : By?,
  to : By?,
) -> Array[Traverser] raise Refused {
  let out : Array[Traverser] = []
  for traverser in input {
    let current = match traverser.value {
      Vertex(vertex) => vertex
      _ =>
        match
          traverser.path
          .rev_iter()
          .find_first(fn(value) {
            match value {
              Vertex(_) => true
              _ => false
            }
          }) {
          Some(Vertex(vertex)) => vertex
          _ =>
            raise Refused::Mismatch(
              "addE()",
              traverser.value.to_text(),
              "a vertex",
            )
        }
    }
    let from_vertex = resolve_endpoint(ctx, from, traverser, current)
    let to_vertex = resolve_endpoint(ctx, to, traverser, current)
    let edge = ctx.graph.add_edge(from_vertex.id(), label, to_vertex.id(), None)
    for property in properties {
      ctx.graph.put_property(Element::Edge(edge), property.0, property.1)
    }
    out.push(advance(traverser, Value::Edge(edge)))
  }
  out
}

///|
fn resolve_endpoint(
  ctx : Ctx,
  endpoint : By?,
  traverser : Traverser,
  fallback : Vertex,
) -> Vertex raise Refused {
  match endpoint {
    None => fallback
    Some(by) =>
      match by.key {
        Some(name) =>
          match lookup_label(traverser, name, Pop::Last) {
            Some(Vertex(vertex)) => vertex
            _ => raise Refused::Mismatch("addE()", name, "a labelled vertex")
          }
        None =>
          match by.traversal {
            Some(traversal) =>
              match run_on(ctx, traversal, traverser) {
                [first, ..] =>
                  match first.value {
                    Vertex(vertex) => vertex
                    _ =>
                      raise Refused::Mismatch(
                        "addE()",
                        first.value.to_text(),
                        "a vertex",
                      )
                  }
                _ =>
                  raise Refused::Mismatch("addE()", "no vertex", "one vertex")
              }
            None => fallback
          }
      }
  }
}

///|
fn step_property(
  ctx : Ctx,
  input : Array[Traverser],
  key : String,
  value : Value,
  cardinality : Cardinality,
) -> Array[Traverser] raise Refused {
  for traverser in input {
    let element = require_element("property()", traverser.value)
    match cardinality {
      Single => ctx.graph.put_property(element, key, value)
      List | Set => ctx.graph.append_property(element, key, value)
    }
  }
  input
}

///|
fn step_drop(ctx : Ctx, input : Array[Traverser]) -> Array[Traverser] {
  for traverser in input {
    match traverser.value {
      Vertex(vertex) => ctx.graph.drop_vertex(vertex.id())
      Edge(edge) => ctx.graph.drop_edge(edge.id())
      _ => ()
    }
  }
  []
}

///|
fn step_inject(
  values : Array[Value],
  input : Array[Traverser],
) -> Array[Traverser] {
  let out : Array[Traverser] = values.map(start_traverser)
  out.append(input)
  out
}

///|
fn step_side_effect(
  ctx : Ctx,
  input : Array[Traverser],
  inner : Traversal,
) -> Array[Traverser] raise Refused {
  for traverser in input {
    run_on(ctx, inner, traverser) |> ignore
  }
  input
}

///|
fn step_cap(ctx : Ctx, keys : Array[String]) -> Array[Traverser] {
  if keys.length() == 1 {
    return ctx.effect(keys[0]).map(start_traverser)
  }
  let entries : Array[(Value, Value)] = keys.map(fn(key) {
    (Value::Text(key), Value::List(ctx.effect(key)))
  })
  [start_traverser(Value::Dict(entries))]
}

///|
/// Reads a value through a `by()`: a property key, a token, or a nested
/// traversal whose first result is used.
fn read_by(ctx : Ctx, by : By, value : Value) -> Value raise Refused {
  match by.key {
    Some(key) =>
      match value.element() {
        Some(element) => element.property(key).unwrap_or(Value::Nil)
        None => Value::Nil
      }
    None =>
      match by.token {
        Some(token) => read_token(token, value)
        None =>
          match by.column {
            Some(column) =>
              match value {
                Dict(entries) =>
                  if column == Column::Keys {
                    Value::List(entries.map(fn(entry) { entry.0 }))
                  } else {
                    Value::List(entries.map(fn(entry) { entry.1 }))
                  }
                _ => value
              }
            None =>
              match by.traversal {
                Some(traversal) =>
                  match run_steps(ctx, [start_traverser(value)], traversal, 0) {
                    [first, ..] => first.value
                    _ => Value::Nil
                  }
                None => value
              }
          }
      }
  }
}

///|
fn read_token(token : Token, value : Value) -> Value {
  match token {
    Token::Id =>
      match value {
        Vertex(vertex) => vertex.id()
        Edge(edge) => edge.id()
        _ => Value::Nil
      }
    Token::Label =>
      match value {
        Vertex(vertex) => Value::Text(vertex.label())
        Edge(edge) => Value::Text(edge.label())
        _ => Value::Nil
      }
    Token::Key =>
      match value {
        Property(property) => Value::Text(property.key())
        _ => Value::Nil
      }
    Token::Value =>
      match value {
        Property(property) => property.value()
        _ => Value::Nil
      }
  }
}

///|
/// Applies the `by()` in position `index` of a barrier step, cycling when the
/// step has fewer mappings than values.
fn read_by_at(
  ctx : Ctx,
  bys : Array[By],
  index : Int32,
  value : Value,
) -> Value raise Refused {
  if bys.is_empty() {
    value
  } else {
    read_by(ctx, bys[index % bys.length()], value)
  }
}

///|
fn require_element(step : String, value : Value) -> Element raise Refused {
  match value.element() {
    Some(element) => element
    None =>
      raise Refused::Mismatch(step, value.to_text(), "a vertex or an edge")
  }
}

///|
fn require_vertex(step : String, value : Value) -> Vertex raise Refused {
  match value {
    Vertex(vertex) => vertex
    _ => raise Refused::Mismatch(step, value.to_text(), "a vertex")
  }
}

///|
fn require_edge(step : String, value : Value) -> Edge raise Refused {
  match value {
    Edge(edge) => edge
    _ => raise Refused::Mismatch(step, value.to_text(), "an edge")
  }
}

///|
/// The value bound to a label by `as()`, honouring how many of them to take.
fn lookup_label(traverser : Traverser, name : String, pop : Pop) -> Value? {
  let matches = traverser.labels.filter(fn(entry) { entry.0 == name })
  match pop {
    Pop::First => matches.get(0).map(fn(entry) { entry.2 })
    Pop::Last | Pop::Mixed =>
      matches.get(matches.length() - 1).map(fn(entry) { entry.2 })
    Pop::All =>
      if matches.is_empty() {
        None
      } else {
        Some(Value::List(matches.map(fn(entry) { entry.2 })))
      }
  }
}
