// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The order a comparator sorts in.
#derive(Eq)
pub(all) enum Order {
  Asc
  Desc
  Shuffle
}

///|
/// Whether a step works on the whole stream or on each value on its own.
#derive(Eq)
pub(all) enum Scope {
  Global
  Local
}

///|
/// Which value of a labelled step a select reads.
#derive(Eq)
pub(all) enum Pop {
  First
  Last
  All
  Mixed
}

///|
/// The token steps and `valueMap(true)` use to name an element's parts.
#derive(Eq)
pub(all) enum Token {
  Id
  Label
  Key
  Value
}

///|
/// Which half of a map a step reads.
#derive(Eq)
pub(all) enum Column {
  Keys
  Values
}

///|
/// A test on one value, as `has()` and `is()` take it.
pub(all) enum Predicate {
  Equal(Value)
  NotEqual(Value)
  Less(Value)
  LessEqual(Value)
  Greater(Value)
  GreaterEqual(Value)
  Between(Value, Value)
  Inside(Value, Value)
  Outside(Value, Value)
  Within(Array[Value])
  Without(Array[Value])
  StartingWith(String)
  EndingWith(String)
  Containing(String)
  NotStartingWith(String)
  NotEndingWith(String)
  NotContaining(String)
  And(Predicate, Predicate)
  Or(Predicate, Predicate)
  Not(Predicate)
}

///|
pub fn Predicate::accepts(self : Predicate, value : Value) -> Bool {
  match self {
    Equal(want) => value.equals(want)
    NotEqual(want) => !value.equals(want)
    Less(want) => value.compare(want) < 0
    LessEqual(want) => value.compare(want) <= 0
    Greater(want) => value.compare(want) > 0
    GreaterEqual(want) => value.compare(want) >= 0
    Between(low, high) => value.compare(low) >= 0 && value.compare(high) < 0
    Inside(low, high) => value.compare(low) > 0 && value.compare(high) < 0
    Outside(low, high) => value.compare(low) < 0 || value.compare(high) > 0
    Within(options) => options.any(fn(option) { value.equals(option) })
    Without(options) => !options.any(fn(option) { value.equals(option) })
    StartingWith(prefix) =>
      match value {
        Text(text) => text.has_prefix(prefix)
        _ => false
      }
    EndingWith(suffix) =>
      match value {
        Text(text) => text.has_suffix(suffix)
        _ => false
      }
    Containing(part) =>
      match value {
        Text(text) => text.contains(part)
        _ => false
      }
    NotStartingWith(prefix) =>
      match value {
        Text(text) => !text.has_prefix(prefix)
        _ => false
      }
    NotEndingWith(suffix) =>
      match value {
        Text(text) => !text.has_suffix(suffix)
        _ => false
      }
    NotContaining(part) =>
      match value {
        Text(text) => !text.contains(part)
        _ => false
      }
    And(left, right) => left.accepts(value) && right.accepts(value)
    Or(left, right) => left.accepts(value) || right.accepts(value)
    Not(inner) => !inner.accepts(value)
  }
}

///|
/// How a step maps a value before it uses it: a property key, a traversal, a
/// token or a map column. `by()` with no argument is the identity, which is
/// what an absent `By` means.
pub(all) struct By {
  key : String?
  traversal : Traversal?
  token : Token?
  column : Column?
}

///|
pub fn By::identity() -> By {
  { key: None, traversal: None, token: None, column: None, }
}

///|
pub fn By::of_key(key : String) -> By {
  { key: Some(key), traversal: None, token: None, column: None, }
}

///|
pub fn By::of_traversal(traversal : Traversal) -> By {
  { key: None, traversal: Some(traversal), token: None, column: None, }
}

///|
pub fn By::of_token(token : Token) -> By {
  { key: None, traversal: None, token: Some(token), column: None, }
}

///|
pub fn By::of_column(column : Column) -> By {
  { key: None, traversal: None, token: None, column: Some(column), }
}

///|
/// One `by()` of a barrier step: how to read the value and which order to sort
/// in.
pub(all) struct Comparator {
  by : By
  order : Order
}

///|
pub fn Comparator::of(by : By) -> Comparator {
  { by, order: Order::Asc, }
}

///|
/// What `has()` looks for on an element: the property key and the test applied
/// to each of its values.
pub(all) struct Has {
  key : String
  predicate : Predicate
}

///|
/// The state a `repeat()` step needs.
pub(all) struct Repeat {
  body : Traversal
  until : Traversal?
  /// True when `until()` was written before `repeat()`: the body runs before
  /// the test, so a step is taken even when the test already holds.
  until_first : Bool
  emit : Traversal?
  emit_first : Bool
  times : Int64?
}

///|
pub fn Repeat::of(body : Traversal) -> Repeat {
  {
    body,
    until: None,
    until_first: false,
    emit: None,
    emit_first: false,
    times: None,
  }
}

///|
/// The state a `choose()` step needs. Exactly one of `predicate`, `choice` and
/// `on` is set; `options` carries `option()` branches keyed by value.
pub(all) struct Choose {
  predicate : Predicate?
  choice : Traversal?
  on : By?
  then : Traversal?
  otherwise : Traversal?
  options : Array[(Value, Traversal)]
}

///|
pub fn Choose::of_predicate(predicate : Predicate) -> Choose {
  {
    predicate: Some(predicate),
    choice: None,
    on: None,
    then: None,
    otherwise: None,
    options: [],
  }
}

///|
pub fn Choose::of_traversal(choice : Traversal) -> Choose {
  {
    predicate: None,
    choice: Some(choice),
    on: None,
    then: None,
    otherwise: None,
    options: [],
  }
}

///|
pub fn Choose::of_value(on : By) -> Choose {
  {
    predicate: None,
    choice: None,
    on: Some(on),
    then: None,
    otherwise: None,
    options: [],
  }
}

///|
/// One key of a `select()`: a label, or a column of the map being read.
pub(all) enum SelectKey {
  Name(String)
  Column(Column)
}

///|
pub fn SelectKey::to_text(self : SelectKey) -> String {
  match self {
    Name(name) => name
    Column(Column::Keys) => "keys"
    Column(Column::Values) => "values"
  }
}

///|
/// What `where()` filters with.
pub(all) enum WhereKind {
  Traversal(Traversal)
  Predicate(Predicate)
  /// `where("a", P.eq("b"))`: compare the value bound to one label with a
  /// value or with another label.
  Label(String, Predicate)
}

///|
/// One step of a traversal. A traversal is the query plan: the parser, the
/// embedded builder and the openCypher planner all produce steps, and the
/// executor walks them over a stream of traversers. Adding a step therefore
/// means adding one variant here and one case in the engine, never a second
/// plan representation.
pub(all) enum Step {
  /// `V(ids)`: start from vertices, all of them when no id is given.
  Vertices(Array[Value])
  /// `E(ids)`.
  Edges(Array[Value])
  AddVertex(String, Array[(String, Value)])
  AddEdge(String, Array[(String, Value)], By?, By?)
  Out(Array[String])
  In(Array[String])
  Both(Array[String])
  OutEdges(Array[String])
  InEdges(Array[String])
  BothEdges(Array[String])
  OutVertex
  InVertex
  BothVertices
  OtherVertex
  HasLabel(Array[String])
  HasId(Array[Value])
  HasKey(Array[String])
  HasValue(Array[Value])
  Has(Has)
  HasNot(Array[String])
  Values(Array[String])
  ValueMap(Array[String], Array[By], Bool)
  ElementMap(Array[String], Array[By])
  PropertyMap(Array[String], Array[By])
  Properties(Array[String], Array[By])
  ElementKey
  ElementValue
  ElementLabel
  ElementId
  Count(Scope)
  Sum(Scope, Array[By])
  Mean(Scope, Array[By])
  Max(Scope, Array[By])
  Min(Scope, Array[By])
  Fold(Scope)
  Unfold
  Limit(Int64, Scope)
  Skip(Int64, Scope)
  Range(Int64, Int64, Scope)
  Tail(Int64, Scope)
  Dedup(Array[String], Array[By], Scope)
  Order(Scope, Array[Comparator])
  Group(String?, Array[Comparator])
  GroupCount(String?, By?)
  Cap(Array[String])
  PathStep(Array[By], By?, By?)
  SimplePath
  CyclicPath
  Select(Array[SelectKey], Array[By], Pop)
  WhereStep(WhereKind)
  FilterStep(Traversal)
  NotStep(Traversal)
  AndStep(Array[Traversal])
  OrStep(Array[Traversal])
  Is(Predicate)
  Constant(Value)
  MapStep(Traversal, Scope)
  FlatMapStep(Traversal)
  LocalStep(Traversal)
  RepeatStep(Repeat)
  Coalesce(Array[Traversal])
  OptionalStep(Traversal)
  Union(Array[Traversal])
  ChooseStep(Choose)
  Inject(Array[Value])
  Aggregate(String, Scope, By?)
  Store(String, Scope, By?)
  SideEffect(Traversal)
  Project(Array[String], Array[By])
  Sample(Int64, Scope)
  Loops
  Drop
  PropertyStep(String, Value, Cardinality)
  As(String)
  Identity
}

///|
/// How `property()` stores a value: replacing the key's value, adding a value,
/// or adding it only when the key is empty.
#derive(Eq)
pub(all) enum Cardinality {
  Single
  List
  Set
}

///|
/// A sequence of steps: the query plan for one traversal.
pub(all) struct Traversal {
  steps : Array[Step]
}

///|
pub fn Traversal::new() -> Traversal {
  { steps: [], }
}

///|
pub fn Traversal::of(steps : Array[Step]) -> Traversal {
  { steps, }
}

///|
/// Appends a step and returns the traversal, so a traversal reads in step order.
pub fn Traversal::then(self : Traversal, step : Step) -> Traversal {
  self.steps.push(step)
  self
}

///|
pub fn Traversal::is_empty(self : Traversal) -> Bool {
  self.steps.is_empty()
}

///|
pub fn Traversal::size(self : Traversal) -> Int32 {
  self.steps.length()
}

///|
/// The text form of the plan, for messages and tests. It is not the Gremlin
/// someone wrote: the parser has already resolved abbreviations.
pub fn Traversal::to_text(self : Traversal) -> String {
  self.steps.map(fn(step) { step.to_text() }).join(".")
}

///|
pub fn Step::to_text(self : Step) -> String {
  match self {
    Vertices(ids) => "V(" + join_values(ids) + ")"
    Edges(ids) => "E(" + join_values(ids) + ")"
    AddVertex(label, _) => "addV(" + label + ")"
    AddEdge(label, _, _, _) => "addE(" + label + ")"
    Out(labels) => "out(" + labels.join(",") + ")"
    In(labels) => "in(" + labels.join(",") + ")"
    Both(labels) => "both(" + labels.join(",") + ")"
    OutEdges(labels) => "outE(" + labels.join(",") + ")"
    InEdges(labels) => "inE(" + labels.join(",") + ")"
    BothEdges(labels) => "bothE(" + labels.join(",") + ")"
    OutVertex => "outV()"
    InVertex => "inV()"
    BothVertices => "bothV()"
    OtherVertex => "otherV()"
    HasLabel(labels) => "hasLabel(" + labels.join(",") + ")"
    HasId(ids) => "hasId(" + join_values(ids) + ")"
    HasKey(keys) => "hasKey(" + keys.join(",") + ")"
    HasValue(values) => "hasValue(" + join_values(values) + ")"
    Has(has) => "has(" + has.key + ")"
    HasNot(keys) => "hasNot(" + keys.join(",") + ")"
    Values(keys) => "values(" + keys.join(",") + ")"
    ValueMap(keys, _, _) => "valueMap(" + keys.join(",") + ")"
    ElementMap(keys, _) => "elementMap(" + keys.join(",") + ")"
    PropertyMap(keys, _) => "propertyMap(" + keys.join(",") + ")"
    Properties(keys, _) => "properties(" + keys.join(",") + ")"
    ElementKey => "key()"
    ElementValue => "value()"
    ElementLabel => "label()"
    ElementId => "id()"
    Count(_) => "count()"
    Sum(_, _) => "sum()"
    Mean(_, _) => "mean()"
    Max(_, _) => "max()"
    Min(_, _) => "min()"
    Fold(_) => "fold()"
    Unfold => "unfold()"
    Limit(limit, _) => "limit(" + limit.to_string() + ")"
    Skip(offset, _) => "skip(" + offset.to_string() + ")"
    Range(low, high, _) =>
      "range(" + low.to_string() + "," + high.to_string() + ")"
    Tail(limit, _) => "tail(" + limit.to_string() + ")"
    Dedup(_, _, _) => "dedup()"
    Order(_, _) => "order()"
    Group(_, _) => "group()"
    GroupCount(_, _) => "groupCount()"
    Cap(keys) => "cap(" + keys.join(",") + ")"
    PathStep(_, _, _) => "path()"
    SimplePath => "simplePath()"
    CyclicPath => "cyclicPath()"
    Select(keys, _, _) =>
      "select(" + keys.map(fn(key) { key.to_text() }).join(",") + ")"
    WhereStep(_) => "where()"
    FilterStep(_) => "filter()"
    NotStep(_) => "not()"
    AndStep(_) => "and()"
    OrStep(_) => "or()"
    Is(_) => "is()"
    Constant(value) => "constant(" + value.to_text() + ")"
    MapStep(_, _) => "map()"
    FlatMapStep(_) => "flatMap()"
    LocalStep(_) => "local()"
    RepeatStep(_) => "repeat()"
    Coalesce(_) => "coalesce()"
    OptionalStep(_) => "optional()"
    Union(_) => "union()"
    ChooseStep(_) => "choose()"
    Inject(values) => "inject(" + join_values(values) + ")"
    Aggregate(key, _, _) => "aggregate(" + key + ")"
    Store(key, _, _) => "store(" + key + ")"
    SideEffect(_) => "sideEffect()"
    Project(keys, _) => "project(" + keys.join(",") + ")"
    Sample(amount, _) => "sample(" + amount.to_string() + ")"
    Loops => "loops()"
    Drop => "drop()"
    PropertyStep(key, _, _) => "property(" + key + ")"
    As(name) => "as(" + name + ")"
    Identity => "identity()"
  }
}

///|
fn join_values(values : Array[Value]) -> String {
  values.map(fn(value) { value.to_text() }).join(",")
}
