// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a `repeat()` collects from the steps written before it: `until()`,
/// `emit()` and `times()` may sit on either side of the `repeat()`.
priv struct Build {
  steps : Array[@pgq.Step]
  mut until : @pgq.Traversal?
  mut until_first : Bool
  mut emit : @pgq.Traversal?
  mut emit_first : Bool
  mut times : Int64?
}

///|
fn Build::new() -> Build {
  {
    steps: [],
    until: None,
    until_first: false,
    emit: None,
    emit_first: false,
    times: None,
  }
}

///|
/// Parses the text form of a traversal.
///
/// The text starts with `g.` and continues with steps; a parameter is looked up
/// by name in `bindings`, which is how a test supplies the ids it computed.
pub fn parse(
  text : StringView,
  bindings~ : Array[(String, @pgq.Value)] = [],
) -> @pgq.Traversal raise @pgq.Refused {
  let parser = Parser::new(text.to_owned(), bindings)
  parser.skip_space()
  match parser.ident() {
    Some("g") | Some("__") => ()
    Some(other) => raise @pgq.Refused::Malformed(0, other, "g")
    None => raise @pgq.Refused::Malformed(0, "end of input", "g")
  }
  let build = Build::new()
  parse_chain(parser, build)
  parser.skip_space()
  if !parser.at_end() {
    raise parser.fail("the end of the traversal")
  }
  if build.until is Some(_) || build.emit is Some(_) || build.times is Some(_) {
    raise @pgq.Refused::Malformed(parser.at, "a modulation step", "repeat()")
  }
  @pgq.Traversal::of(build.steps)
}

///|
fn parse_chain(parser : Parser, build : Build) -> Unit raise @pgq.Refused {
  while parser.eat('.') {
    let start = parser.at
    let name = match parser.ident() {
      Some(name) => name
      None => raise parser.fail("a step name")
    }
    parser.expect('(', "an argument list")
    let args = parse_args(parser)
    parser.expect(')', "a closing parenthesis")
    apply_step(parser, build, name, args, start)
  }
}

///|
fn parse_args(parser : Parser) -> Array[Arg] raise @pgq.Refused {
  let args : Array[Arg] = []
  parser.skip_space()
  if parser.eat(')') {
    parser.at = parser.at - 1
    return args
  }
  while true {
    args.push(parse_arg(parser))
    if parser.eat(',') {
      continue
    }
    break
  }
  args
}

///|
fn parse_arg(parser : Parser) -> Arg raise @pgq.Refused {
  parser.skip_space()
  match parser.string() {
    Some(text) => return Arg::Value(@pgq.Value::Text(text))
    None => ()
  }
  match parser.number() {
    Some(value) => return Arg::Value(value)
    None => ()
  }
  parser.skip_space()
  if parser.eat('[') {
    return Arg::Value(parse_collection(parser))
  }
  let start = parser.at
  match parser.ident() {
    None => raise parser.fail("an argument")
    Some(name) =>
      match name {
        "true" => Arg::Value(@pgq.Value::Bool(true))
        "false" => Arg::Value(@pgq.Value::Bool(false))
        "null" => Arg::Value(@pgq.Value::Nil)
        "__" => Arg::Trav(parse_anonymous(parser))
        _ => {
          parser.skip_space()
          if parser.eat('.') {
            parse_qualified(parser, name, start)
          } else if parser.at < parser.text.length() &&
            char_at(parser.text, parser.at) == '(' {
            if is_predicate_name(name) {
              parse_predicate_call(parser, name)
            } else {
              Arg::Trav(parse_named_anonymous(parser, name))
            }
          } else {
            match array_find(parser.bindings, fn(entry) { entry.0 == name }) {
              Some(entry) => Arg::Value(entry.1)
              None =>
                match name {
                  "asc" => Arg::Order(@pgq.Order::Asc)
                  "desc" => Arg::Order(@pgq.Order::Desc)
                  "shuffle" => Arg::Order(@pgq.Order::Shuffle)
                  "local" => Arg::Scope(@pgq.Scope::Local)
                  "global" => Arg::Scope(@pgq.Scope::Global)
                  "keys" => Arg::Column(@pgq.Column::Keys)
                  "values" => Arg::Column(@pgq.Column::Values)
                  _ => raise parser.fail("a parameter named " + name)
                }
            }
          }
        }
      }
  }
}

///|
/// A list `[1, 2]` or a map `["a": 1]`.
fn parse_collection(parser : Parser) -> @pgq.Value raise @pgq.Refused {
  let items : Array[@pgq.Value] = []
  let entries : Array[(@pgq.Value, @pgq.Value)] = []
  let mut is_map = false
  parser.skip_space()
  if parser.eat(']') {
    return @pgq.Value::List([])
  }
  while true {
    let key = match parser.string() {
      Some(text) => @pgq.Value::Text(text)
      None =>
        match parser.number() {
          Some(value) => value
          None => raise parser.fail("a list item")
        }
    }
    parser.skip_space()
    if parser.eat(':') {
      is_map = true
      let value = match parse_arg(parser) {
        Arg::Value(value) => value
        _ => raise parser.fail("a value")
      }
      entries.push((key, value))
    } else {
      items.push(key)
    }
    if parser.eat(',') {
      continue
    }
    break
  }
  parser.expect(']', "a closing bracket")
  if is_map {
    @pgq.Value::Dict(entries)
  } else {
    @pgq.Value::List(items)
  }
}

///|
fn parse_anonymous(parser : Parser) -> @pgq.Traversal raise @pgq.Refused {
  let build = Build::new()
  parse_chain(parser, build)
  @pgq.Traversal::of(build.steps)
}

///|
/// An anonymous traversal written without its `__.` prefix, as
/// `repeat(out())` and `by(label())` do.
fn parse_named_anonymous(
  parser : Parser,
  name : String,
) -> @pgq.Traversal raise @pgq.Refused {
  let build = Build::new()
  parser.expect('(', "an argument list")
  let args = parse_args(parser)
  parser.expect(')', "a closing parenthesis")
  apply_step(parser, build, name, args, 0)
  parse_chain(parser, build)
  @pgq.Traversal::of(build.steps)
}

///|
fn is_predicate_name(name : String) -> Bool {
  match name {
    "eq"
    | "neq"
    | "lt"
    | "lte"
    | "gt"
    | "gte"
    | "between"
    | "inside"
    | "outside"
    | "within"
    | "without"
    | "startingWith"
    | "endingWith"
    | "containing"
    | "notStartingWith"
    | "notEndingWith"
    | "notContaining"
    | "not"
    | "and"
    | "or" => true
    _ => false
  }
}

///|
/// A dotted name: an enum constant such as `@pgq.Order.desc`, or a predicate such as
/// `P.gt(1)`.
fn parse_qualified(
  parser : Parser,
  owner : String,
  at : Int32,
) -> Arg raise @pgq.Refused {
  let const_name = match parser.ident() {
    Some(const_name) => const_name
    None => raise parser.fail("a constant or a const_name name")
  }
  parser.skip_space()
  let takes_arguments = parser.at < parser.text.length() &&
    char_at(parser.text, parser.at) == '('
  if owner == "P" || owner == "TextP" {
    return Arg::Pred(parse_predicate_const_name(parser, const_name))
  }
  guard !takes_arguments else {
    raise @pgq.Refused::Unsupported(
      owner + "." + const_name,
      "a call on a constant",
    )
  }
  match owner {
    "@pgq.Order" =>
      match const_name {
        "asc" => Arg::Order(@pgq.Order::Asc)
        "desc" => Arg::Order(@pgq.Order::Desc)
        "shuffle" => Arg::Order(@pgq.Order::Shuffle)
        _ =>
          raise @pgq.Refused::Unsupported(
            "@pgq.Order." + const_name,
            "an order",
          )
      }
    "@pgq.Scope" =>
      match const_name {
        "local" => Arg::Scope(@pgq.Scope::Local)
        "global" => Arg::Scope(@pgq.Scope::Global)
        _ =>
          raise @pgq.Refused::Unsupported("@pgq.Scope." + const_name, "a scope")
      }
    "@pgq.Column" =>
      match const_name {
        "keys" => Arg::Column(@pgq.Column::Keys)
        "values" => Arg::Column(@pgq.Column::Values)
        _ =>
          raise @pgq.Refused::Unsupported(
            "@pgq.Column." + const_name,
            "a column",
          )
      }
    "T" =>
      match const_name {
        "id" => Arg::Token(@pgq.Token::Id)
        "label" => Arg::Token(@pgq.Token::Label)
        "key" => Arg::Token(@pgq.Token::Key)
        "value" => Arg::Token(@pgq.Token::@pgq.Value)
        _ => raise @pgq.Refused::Unsupported("T." + const_name, "a token")
      }
    "@pgq.Pop" =>
      match const_name {
        "first" => Arg::Pop(@pgq.Pop::First)
        "last" => Arg::Pop(@pgq.Pop::Last)
        "all" => Arg::Pop(@pgq.Pop::All)
        "mixed" => Arg::Pop(@pgq.Pop::Mixed)
        _ => raise @pgq.Refused::Unsupported("@pgq.Pop." + const_name, "a pop")
      }
    "@pgq.Cardinality" =>
      match const_name {
        "single" => Arg::Cardinality(@pgq.Cardinality::Single)
        "list" => Arg::Cardinality(@pgq.Cardinality::List)
        "set" => Arg::Cardinality(@pgq.Cardinality::Set)
        _ =>
          raise @pgq.Refused::Unsupported(
            "@pgq.Cardinality." + const_name,
            "a cardinality",
          )
      }
    _ =>
      raise @pgq.Refused::Malformed(
        at,
        owner + "." + const_name,
        "a known constant",
      )
  }
}

///|
/// A predicate written as a bare call, the way `has("age", within(1, 2))` uses
/// the statically imported helpers.
fn parse_predicate_call(
  parser : Parser,
  name : String,
) -> Arg raise @pgq.Refused {
  parser.expect('(', "an argument list")
  let predicate = parse_predicate(parser, name)
  parser.expect(')', "a closing parenthesis")
  Arg::Pred(predicate)
}

///|
fn parse_predicate_const_name(
  parser : Parser,
  name : String,
) -> @pgq.Predicate raise @pgq.Refused {
  parser.expect('(', "an argument list")
  let predicate = parse_predicate(parser, name)
  parser.expect(')', "a closing parenthesis")
  predicate
}

///|
fn parse_predicate(
  parser : Parser,
  name : String,
) -> @pgq.Predicate raise @pgq.Refused {
  match name {
    "eq" => @pgq.Predicate::Equal(one_value(parser, name))
    "neq" => @pgq.Predicate::NotEqual(one_value(parser, name))
    "lt" => @pgq.Predicate::Less(one_value(parser, name))
    "lte" => @pgq.Predicate::LessEqual(one_value(parser, name))
    "gt" => @pgq.Predicate::Greater(one_value(parser, name))
    "gte" => @pgq.Predicate::GreaterEqual(one_value(parser, name))
    "between" => {
      let (low, high) = two_values(parser, name)
      @pgq.Predicate::Between(low, high)
    }
    "inside" => {
      let (low, high) = two_values(parser, name)
      @pgq.Predicate::Inside(low, high)
    }
    "outside" => {
      let (low, high) = two_values(parser, name)
      @pgq.Predicate::Outside(low, high)
    }
    "within" => @pgq.Predicate::Within(many_values(parser))
    "without" => @pgq.Predicate::Without(many_values(parser))
    "startingWith" => @pgq.Predicate::StartingWith(one_text(parser, name))
    "endingWith" => @pgq.Predicate::EndingWith(one_text(parser, name))
    "containing" => @pgq.Predicate::Containing(one_text(parser, name))
    "notStartingWith" => @pgq.Predicate::NotStartingWith(one_text(parser, name))
    "notEndingWith" => @pgq.Predicate::NotEndingWith(one_text(parser, name))
    "notContaining" => @pgq.Predicate::NotContaining(one_text(parser, name))
    "not" => @pgq.Predicate::Not(one_predicate(parser, name))
    "and" => {
      let left = one_predicate(parser, name)
      parser.expect(',', "a second predicate")
      @pgq.Predicate::And(left, parse_predicate(parser, predicate_name(parser)))
    }
    "or" => {
      let left = one_predicate(parser, name)
      parser.expect(',', "a second predicate")
      @pgq.Predicate::Or(left, parse_predicate(parser, predicate_name(parser)))
    }
    _ => raise @pgq.Refused::Unsupported("P." + name, "a predicate")
  }
}

///|
fn predicate_name(parser : Parser) -> String raise @pgq.Refused {
  match parser.ident() {
    Some(name) => name
    None => raise parser.fail("a predicate name")
  }
}

///|
fn one_value(parser : Parser, name : String) -> @pgq.Value raise @pgq.Refused {
  match parse_arg(parser) {
    Arg::Value(value) => value
    _ => raise @pgq.Refused::Unsupported("P." + name, "a value")
  }
}

///|
fn two_values(
  parser : Parser,
  name : String,
) -> (@pgq.Value, @pgq.Value) raise @pgq.Refused {
  let low = one_value(parser, name)
  parser.skip_space()
  parser.expect(',', "a second value")
  let high = one_value(parser, name)
  (low, high)
}

///|
fn many_values(parser : Parser) -> Array[@pgq.Value] raise @pgq.Refused {
  let values : Array[@pgq.Value] = []
  parser.skip_space()
  if parser.eat(')') {
    parser.at = parser.at - 1
    return values
  }
  while true {
    values.push(one_value(parser, "within"))
    if parser.eat(',') {
      continue
    }
    break
  }
  values
}

///|
fn one_text(parser : Parser, name : String) -> String raise @pgq.Refused {
  match one_value(parser, name) {
    @pgq.Value::Text(text) => text
    other => raise @pgq.Refused::Unsupported("P." + name, other.to_text())
  }
}

///|
fn one_predicate(
  parser : Parser,
  _name : String,
) -> @pgq.Predicate raise @pgq.Refused {
  let const_name = predicate_name(parser)
  parser.expect('(', "an argument list")
  let predicate = parse_predicate(parser, const_name)
  parser.expect(')', "a closing parenthesis")
  predicate
}
