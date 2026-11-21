// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Turns one written step into a plan step, or records a modulation that the
/// step before it, or the `repeat()` after it, will take.
fn apply_step(
  parser : Parser,
  build : Build,
  name : String,
  args : Array[Arg],
  at : Int32,
) -> Unit raise @pgq.Refused {
  match name {
    "by" => attach_by(parser, build, args)
    "from" => attach_end(parser, build, args, true)
    "to" => attach_end(parser, build, args, false)
    "option" => attach_option(parser, build, args)
    "until" => record_until(build, first_traversal(parser, args, "until"))
    "emit" => record_emit(build, args)
    "times" => record_times(build, args)
    "repeat" => record_repeat(parser, build, args)
    "has" =>
      if args.length() == 3 {
        // has(label, key, value) restricts both the label and one property.
        let label = text_at(args, 0).unwrap_or("")
        let rest : Array[Arg] = [args[1], args[2]]
        build.steps.push(@pgq.Step::HasLabel([label]))
        build.steps.push(@pgq.Step::Has(parse_has(rest)))
      } else {
        build.steps.push(@pgq.Step::Has(parse_has(args)))
      }
    "withStrategies"
    | "withoutStrategies"
    | "with"
    | "withSack"
    | "withBulk"
    | "withPath"
    | "withSideEffect"
    | "without" => ()
    "barrier" => build.steps.push(@pgq.Step::Identity)
    _ => build.steps.push(build_step(parser, name, args, at))
  }
}

///|
fn build_step(
  parser : Parser,
  name : String,
  args : Array[Arg],
  _at : Int32,
) -> @pgq.Step raise @pgq.Refused {
  match name {
    "V" => @pgq.Step::Vertices(values_of(args))
    "E" => @pgq.Step::Edges(values_of(args))
    "addV" => @pgq.Step::AddVertex(text_at(args, 0).unwrap_or(""), [])
    "addE" => @pgq.Step::AddEdge(text_at(args, 0).unwrap_or(""), [], None, None)
    "out" => @pgq.Step::Out(labels(args))
    "in" => @pgq.Step::In(labels(args))
    "both" => @pgq.Step::Both(labels(args))
    "outE" => @pgq.Step::OutEdges(labels(args))
    "inE" => @pgq.Step::InEdges(labels(args))
    "bothE" => @pgq.Step::BothEdges(labels(args))
    "outV" => @pgq.Step::OutVertex
    "inV" => @pgq.Step::InVertex
    "bothV" => @pgq.Step::BothVertices
    "otherV" => @pgq.Step::OtherVertex
    "hasLabel" => @pgq.Step::HasLabel(labels(args))
    "hasId" => @pgq.Step::HasId(values_of(args))
    "hasKey" => @pgq.Step::HasKey(labels(args))
    "hasValue" => @pgq.Step::HasValue(values_of(args))
    "hasNot" => @pgq.Step::HasNot(labels(args))
    "has" => @pgq.Step::Has(parse_has(args))
    "values" => @pgq.Step::Values(labels(args))
    "valueMap" => @pgq.Step::ValueMap(keys_with_flag(args), [], has_true(args))
    "elementMap" => @pgq.Step::ElementMap(labels(args), [])
    "propertyMap" => @pgq.Step::PropertyMap(labels(args), [])
    "properties" => @pgq.Step::Properties(labels(args), [])
    "key" => @pgq.Step::ElementKey
    "value" => @pgq.Step::ElementValue
    "label" => @pgq.Step::ElementLabel
    "id" => @pgq.Step::ElementId
    "count" => @pgq.Step::Count(scope_at(args))
    "sum" => @pgq.Step::Sum(scope_at(args), [])
    "mean" => @pgq.Step::Mean(scope_at(args), [])
    "max" => @pgq.Step::Max(scope_at(args), [])
    "min" => @pgq.Step::Min(scope_at(args), [])
    "fold" => @pgq.Step::Fold(scope_at(args))
    "unfold" => @pgq.Step::Unfold
    "limit" => @pgq.Step::Limit(number_at(args, 0), scope_at(args))
    "skip" => @pgq.Step::Skip(number_at(args, 0), scope_at(args))
    "range" =>
      @pgq.Step::Range(number_at(args, 0), number_at(args, 1), scope_at(args))
    "tail" => @pgq.Step::Tail(number_at(args, 0), scope_at(args))
    "dedup" => @pgq.Step::Dedup(labels(args), [], scope_at(args))
    "order" => @pgq.Step::Order(scope_at(args), [])
    "group" => @pgq.Step::Group(text_at(args, 0), [])
    "groupCount" => @pgq.Step::GroupCount(text_at(args, 0), None)
    "cap" => @pgq.Step::Cap(labels(args))
    "path" => @pgq.Step::PathStep([], None, None)
    "simplePath" => @pgq.Step::SimplePath
    "cyclicPath" => @pgq.Step::CyclicPath
    "select" => @pgq.Step::Select(select_keys(args), [], @pgq.Pop::Last)
    "where" => @pgq.Step::WhereStep(parse_where(args))
    "filter" => @pgq.Step::FilterStep(first_traversal(parser, args, "filter"))
    "not" => @pgq.Step::NotStep(first_traversal(parser, args, "not"))
    "and" => @pgq.Step::AndStep(traversals(args))
    "or" => @pgq.Step::OrStep(traversals(args))
    "is" => @pgq.Step::Is(predicate_at(args))
    "constant" =>
      @pgq.Step::Constant(value_at(args, 0).unwrap_or(@pgq.Value::Nil))
    "map" =>
      @pgq.Step::MapStep(
        first_traversal(parser, args, "map"),
        @pgq.Scope::Global,
      )
    "flatMap" =>
      @pgq.Step::FlatMapStep(first_traversal(parser, args, "flatMap"))
    "local" => @pgq.Step::LocalStep(first_traversal(parser, args, "local"))
    "coalesce" => @pgq.Step::Coalesce(traversals(args))
    "optional" =>
      @pgq.Step::OptionalStep(first_traversal(parser, args, "optional"))
    "union" => @pgq.Step::Union(traversals(args))
    "choose" => @pgq.Step::ChooseStep(parse_choose(args))
    "inject" => @pgq.Step::Inject(values_of(args))
    "aggregate" =>
      @pgq.Step::Aggregate(
        text_at(args, 0).unwrap_or(""),
        @pgq.Scope::Global,
        None,
      )
    "store" =>
      @pgq.Step::Store(text_at(args, 0).unwrap_or(""), @pgq.Scope::Global, None)
    "sideEffect" =>
      @pgq.Step::SideEffect(first_traversal(parser, args, "sideEffect"))
    "project" => @pgq.Step::Project(labels(args), [])
    "sample" => @pgq.Step::Sample(number_at(args, 0), scope_at(args))
    "loops" => @pgq.Step::Loops
    "drop" => @pgq.Step::Drop
    "property" => parse_property(args)
    "as" => @pgq.Step::As(text_at(args, 0).unwrap_or(""))
    "identity" => @pgq.Step::Identity
    _ => raise @pgq.Refused::Unsupported(name, "this step")
  }
}

///|
/// The values of the arguments that are plain values.
fn values_of(args : Array[Arg]) -> Array[@pgq.Value] {
  let out : Array[@pgq.Value] = []
  for arg in args {
    match arg {
      Value(value) => out.push(value)
      _ => ()
    }
  }
  out
}

///|
/// The text of every string argument, which is what a step's labels are.
fn labels(args : Array[Arg]) -> Array[String] {
  let out : Array[String] = []
  for arg in args {
    match arg {
      Value(@pgq.Value::Text(text)) => out.push(text)
      _ => ()
    }
  }
  out
}

///|
fn text_at(args : Array[Arg], index : Int32) -> String? {
  match args.get(index) {
    Some(Value(@pgq.Value::Text(text))) => Some(text)
    _ => None
  }
}

///|
fn value_at(args : Array[Arg], index : Int32) -> @pgq.Value? {
  match args.get(index) {
    Some(Value(value)) => Some(value)
    _ => None
  }
}

///|
/// The scope an argument list starts with, defaulting to the whole stream.
fn scope_at(args : Array[Arg]) -> @pgq.Scope {
  match args.get(0) {
    Some(Scope(scope)) => scope
    _ => @pgq.Scope::Global
  }
}

///|
/// A count argument: the first one when there is no scope, the second when the
/// step wrote `limit(local, 2)`.
fn number_at(args : Array[Arg], index : Int32) -> Int64 {
  let offset = match args.get(0) {
    Some(Scope(_)) => 1
    _ => 0
  }
  match args.get(offset + index) {
    Some(Value(@pgq.Value::Int(count))) => count
    Some(Value(@pgq.Value::Double(count))) => count.to_int64()
    _ => 0L
  }
}

///|
fn has_true(args : Array[Arg]) -> Bool {
  for arg in args {
    match arg {
      Value(@pgq.Value::Bool(true)) => return true
      _ => ()
    }
  }
  false
}

///|
fn keys_with_flag(args : Array[Arg]) -> Array[String] {
  labels(args)
}

///|
fn select_keys(args : Array[Arg]) -> Array[@pgq.SelectKey] {
  let out : Array[@pgq.SelectKey] = []
  for arg in args {
    match arg {
      Value(@pgq.Value::Text(text)) => out.push(@pgq.SelectKey::Name(text))
      Column(column) => out.push(@pgq.SelectKey::Column(column))
      _ => ()
    }
  }
  out
}

///|
fn traversals(args : Array[Arg]) -> Array[@pgq.Traversal] {
  let out : Array[@pgq.Traversal] = []
  for arg in args {
    match arg {
      Trav(traversal) => out.push(traversal)
      _ => ()
    }
  }
  out
}

///|
fn first_traversal(
  _parser : Parser,
  args : Array[Arg],
  name : String,
) -> @pgq.Traversal raise @pgq.Refused {
  for arg in args {
    match arg {
      Trav(traversal) => return traversal
      _ => ()
    }
  }
  raise @pgq.Refused::Unsupported(name, "a traversal argument")
}

///|
fn predicate_at(args : Array[Arg]) -> @pgq.Predicate {
  match args.get(0) {
    Some(Pred(predicate)) => predicate
    Some(Value(value)) => @pgq.Predicate::Equal(value)
    _ => @pgq.Predicate::Not(@pgq.Predicate::Equal(@pgq.Value::Nil))
  }
}

///|
/// `has(key)` tests that the key exists; `has(key, predicate)` tests its values.
fn parse_has(args : Array[Arg]) -> @pgq.Has {
  let key = text_at(args, 0).unwrap_or("")
  let predicate = match args.get(1) {
    Some(Pred(predicate)) => predicate
    Some(Value(value)) => @pgq.Predicate::Equal(value)
    _ => @pgq.Predicate::Not(@pgq.Predicate::Equal(@pgq.Value::Nil))
  }
  { key, predicate, }
}

///|
fn parse_where(args : Array[Arg]) -> @pgq.WhereKind raise @pgq.Refused {
  match args.get(0) {
    Some(Trav(traversal)) => @pgq.WhereKind::Traversal(traversal)
    Some(Pred(predicate)) => @pgq.WhereKind::Predicate(predicate)
    Some(Value(@pgq.Value::Text(name))) =>
      match args.get(1) {
        Some(Pred(predicate)) => @pgq.WhereKind::Label(name, predicate)
        _ => raise @pgq.Refused::Unsupported("where", "a label and a predicate")
      }
    _ => raise @pgq.Refused::Unsupported("where", "a traversal or a predicate")
  }
}

///|
fn parse_property(args : Array[Arg]) -> @pgq.Step raise @pgq.Refused {
  match args.get(0) {
    Some(Cardinality(cardinality)) => {
      let key = match text_at(args, 1) {
        Some(key) => key
        None => raise @pgq.Refused::Unsupported("property", "a key")
      }
      @pgq.Step::PropertyStep(
        key,
        value_at(args, 2).unwrap_or(@pgq.Value::Nil),
        cardinality,
      )
    }
    Some(_) => {
      let key = match text_at(args, 0) {
        Some(key) => key
        None => raise @pgq.Refused::Unsupported("property", "a key")
      }
      @pgq.Step::PropertyStep(
        key,
        value_at(args, 1).unwrap_or(@pgq.Value::Nil),
        @pgq.Cardinality::Single,
      )
    }
    None => raise @pgq.Refused::Unsupported("property", "a key")
  }
}

///|
fn parse_choose(args : Array[Arg]) -> @pgq.Choose raise @pgq.Refused {
  match args.get(0) {
    Some(Pred(predicate)) => {
      let choose = @pgq.Choose::of_predicate(predicate)
      {
        predicate: choose.predicate,
        choice: choose.choice,
        on: choose.on,
        then: traversal_at(args, 1),
        otherwise: traversal_at(args, 2),
        options: ([] : Array[(@pgq.OptionKey, @pgq.Traversal)]),
      }
    }
    Some(Trav(traversal)) => {
      let choose = @pgq.Choose::of_traversal(traversal)
      {
        predicate: choose.predicate,
        choice: choose.choice,
        on: choose.on,
        then: traversal_at(args, 1),
        otherwise: traversal_at(args, 2),
        options: ([] : Array[(@pgq.OptionKey, @pgq.Traversal)]),
      }
    }
    Some(Column(column)) => @pgq.Choose::of_value(@pgq.By::of_column(column))
    Some(Token(token)) => @pgq.Choose::of_value(@pgq.By::of_token(token))
    Some(Value(value)) =>
      @pgq.Choose::of_value(
        @pgq.By::of_traversal(
          @pgq.Traversal::new().then(@pgq.Step::Constant(value)),
        ),
      )
    _ =>
      raise @pgq.Refused::Unsupported(
        "choose", "a predicate, a traversal or a value",
      )
  }
}

///|
fn traversal_at(args : Array[Arg], index : Int32) -> @pgq.Traversal? {
  match args.get(index) {
    Some(Trav(traversal)) => Some(traversal)
    _ => None
  }
}

///|
/// `by()` modulates the step before it.
fn attach_by(
  parser : Parser,
  build : Build,
  args : Array[Arg],
) -> Unit raise @pgq.Refused {
  let by = match args.get(0) {
    None => @pgq.By::identity()
    Some(Value(@pgq.Value::Text(key))) => @pgq.By::of_key(key)
    Some(Trav(traversal)) => @pgq.By::of_traversal(traversal)
    Some(Column(column)) => @pgq.By::of_column(column)
    Some(Token(token)) => @pgq.By::of_token(token)
    Some(Order(_)) => @pgq.By::identity()
    Some(_) =>
      raise @pgq.Refused::Unsupported("by", "a key, a traversal or a column")
  }
  let order = match args.get(1) {
    Some(Order(order)) => order
    Some(_) => raise @pgq.Refused::Unsupported("by", "an order")
    None =>
      match args.get(0) {
        Some(Order(order)) => order
        _ => @pgq.Order::Asc
      }
  }
  let last = match build.steps.get(build.steps.length() - 1) {
    Some(step) => step
    None => raise parser.fail("a step for by() to modulate")
  }
  build.steps[build.steps.length() - 1] = with_by(last, by, order)
}

///|
fn with_by(
  step : @pgq.Step,
  by : @pgq.By,
  order : @pgq.Order,
) -> @pgq.Step raise @pgq.Refused {
  match step {
    @pgq.Step::ValueMap(keys, bys, tokens) =>
      @pgq.Step::ValueMap(keys, bys + [by], tokens)
    @pgq.Step::ElementMap(keys, bys) => @pgq.Step::ElementMap(keys, bys + [by])
    @pgq.Step::PropertyMap(keys, bys) =>
      @pgq.Step::PropertyMap(keys, bys + [by])
    @pgq.Step::Properties(keys, bys) => @pgq.Step::Properties(keys, bys + [by])
    @pgq.Step::Dedup(labels, bys, scope) =>
      @pgq.Step::Dedup(labels, bys + [by], scope)
    @pgq.Step::Order(scope, comparators) =>
      @pgq.Step::Order(scope, comparators + [{ by, order, }])
    @pgq.Step::PathStep(bys, from, to) =>
      @pgq.Step::PathStep(bys + [by], from, to)
    @pgq.Step::Select(keys, bys, pop) =>
      @pgq.Step::Select(keys, bys + [by], pop)
    @pgq.Step::Group(key, comparators) =>
      @pgq.Step::Group(key, comparators + [{ by, order, }])
    @pgq.Step::GroupCount(key, _) => @pgq.Step::GroupCount(key, Some(by))
    @pgq.Step::Sum(scope, bys) => @pgq.Step::Sum(scope, bys + [by])
    @pgq.Step::Mean(scope, bys) => @pgq.Step::Mean(scope, bys + [by])
    @pgq.Step::Max(scope, bys) => @pgq.Step::Max(scope, bys + [by])
    @pgq.Step::Min(scope, bys) => @pgq.Step::Min(scope, bys + [by])
    @pgq.Step::Project(keys, bys) => @pgq.Step::Project(keys, bys + [by])
    @pgq.Step::Aggregate(key, scope, _) =>
      @pgq.Step::Aggregate(key, scope, Some(by))
    @pgq.Step::Store(key, scope, _) => @pgq.Step::Store(key, scope, Some(by))
    _ => raise @pgq.Refused::Unsupported("by", "this step")
  }
}

///|
/// `from()` and `to()` narrow a `path()` and choose the ends of an `addE()`.
fn attach_end(
  parser : Parser,
  build : Build,
  args : Array[Arg],
  is_from : Bool,
) -> Unit raise @pgq.Refused {
  let mark = match args.get(0) {
    Some(Value(@pgq.Value::Text(name))) => @pgq.By::of_key(name)
    Some(Trav(traversal)) => @pgq.By::of_traversal(traversal)
    _ => raise @pgq.Refused::Unsupported("from/to", "a label or a traversal")
  }
  let last = match build.steps.get(build.steps.length() - 1) {
    Some(step) => step
    None => raise parser.fail("a step for from() or to()")
  }
  let updated = match last {
    @pgq.Step::PathStep(bys, from, to) =>
      if is_from {
        @pgq.Step::PathStep(bys, Some(mark), to)
      } else {
        @pgq.Step::PathStep(bys, from, Some(mark))
      }
    @pgq.Step::AddEdge(label, properties, from, to) =>
      if is_from {
        @pgq.Step::AddEdge(label, properties, Some(mark), to)
      } else {
        @pgq.Step::AddEdge(label, properties, from, Some(mark))
      }
    _ => raise @pgq.Refused::Unsupported("from/to", last.to_text())
  }
  build.steps[build.steps.length() - 1] = updated
}

///|
/// `option()` adds a branch to the `choose()` before it.
fn attach_option(
  parser : Parser,
  build : Build,
  args : Array[Arg],
) -> Unit raise @pgq.Refused {
  let key = match args.get(0) {
    Some(Value(value)) => @pgq.OptionKey::Value(value)
    Some(Pred(predicate)) => @pgq.OptionKey::Predicate(predicate)
    Some(Pick(name)) =>
      if name == "none" {
        @pgq.OptionKey::Default
      } else {
        raise @pgq.Refused::Unsupported("option", "Pick." + name)
      }
    _ => raise @pgq.Refused::Unsupported("option", "a value")
  }
  let branch = match args.get(1) {
    Some(Trav(traversal)) => traversal
    _ => raise @pgq.Refused::Unsupported("option", "a traversal")
  }
  let last = match build.steps.get(build.steps.length() - 1) {
    Some(step) => step
    None => raise parser.fail("a choose() for option()")
  }
  match last {
    @pgq.ChooseStep(choose) =>
      build.steps[build.steps.length() - 1] = @pgq.ChooseStep({
        predicate: choose.predicate,
        choice: choose.choice,
        on: choose.on,
        then: choose.then,
        otherwise: choose.otherwise,
        options: choose.options + [(key, branch)],
      })
    _ => raise @pgq.Refused::Unsupported("option", last.to_text())
  }
}

///|
fn record_until(build : Build, until : @pgq.Traversal) -> Unit {
  match build.steps.get(build.steps.length() - 1) {
    Some(@pgq.Step::RepeatStep(repeat)) =>
      build.steps[build.steps.length() - 1] = @pgq.Step::RepeatStep({
        body: repeat.body,
        until: Some(until),
        until_first: false,
        emit: repeat.emit,
        emit_first: repeat.emit_first,
        times: repeat.times,
      })
    _ => {
      build.until = Some(until)
      build.until_first = true
    }
  }
}

///|
fn record_emit(build : Build, args : Array[Arg]) -> Unit {
  let emit = match args.get(0) {
    Some(Trav(traversal)) => traversal
    _ => @pgq.Traversal::new()
  }
  match build.steps.get(build.steps.length() - 1) {
    Some(@pgq.Step::RepeatStep(repeat)) =>
      build.steps[build.steps.length() - 1] = @pgq.Step::RepeatStep({
        body: repeat.body,
        until: repeat.until,
        until_first: repeat.until_first,
        emit: Some(emit),
        emit_first: false,
        times: repeat.times,
      })
    _ => {
      build.emit = Some(emit)
      build.emit_first = true
    }
  }
}

///|
fn record_times(build : Build, args : Array[Arg]) -> Unit raise @pgq.Refused {
  let times = match args.get(0) {
    Some(Value(@pgq.Value::Int(count))) => count
    Some(Value(@pgq.Value::Double(count))) => count.to_int64()
    _ => raise @pgq.Refused::Unsupported("times", "a number")
  }
  match build.steps.get(build.steps.length() - 1) {
    Some(@pgq.Step::RepeatStep(repeat)) =>
      build.steps[build.steps.length() - 1] = @pgq.Step::RepeatStep({
        body: repeat.body,
        until: repeat.until,
        until_first: repeat.until_first,
        emit: repeat.emit,
        emit_first: repeat.emit_first,
        times: Some(times),
      })
    _ => build.times = Some(times)
  }
}

///|
/// `repeat()` takes whatever `until()`, `emit()` and `times()` were written
/// before it, which is the `until(...).repeat(...)` order.
fn record_repeat(
  parser : Parser,
  build : Build,
  args : Array[Arg],
) -> Unit raise @pgq.Refused {
  let body = first_traversal(parser, args, "repeat")
  build.steps.push(
    @pgq.Step::RepeatStep({
      body,
      until: build.until,
      until_first: build.until_first,
      emit: build.emit,
      emit_first: build.emit_first,
      times: build.times,
    }),
  )
  build.until = None
  build.until_first = false
  build.emit = None
  build.emit_first = false
  build.times = None
}
