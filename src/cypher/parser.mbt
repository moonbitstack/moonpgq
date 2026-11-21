// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Parses a Cypher query into clauses.
///
/// The read clauses are the point: `MATCH` with variable-length paths,
/// `OPTIONAL MATCH`, `WHERE`, `WITH`, `UNWIND`, `RETURN` with aggregation and
/// `ORDER BY`, `SKIP`, `LIMIT`. `CREATE` is here so a fixture can be loaded,
/// which is what the conformance suite does before each read.
pub fn parse(text : StringView) -> Query raise @pgq.Refused {
  let lexer = Lexer::of(text.to_owned())
  let clauses : Array[Clause] = []
  while true {
    match lexer.peek() {
      End => break
      _ => ()
    }
    if lexer.eat_symbol(";") {
      continue
    }
    if lexer.check_word("match") || lexer.check_word("optional") {
      let optional = lexer.check_word("optional")
      if optional {
        lexer.advance()
      }
      lexer.expect_word("match")
      let parts = parse_pattern(lexer)
      let filter = if lexer.eat_word("where") {
        Some(parse_expr(lexer))
      } else {
        None
      }
      clauses.push(Clause::Match(parts, optional, filter))
      continue
    }
    if lexer.eat_word("where") {
      clauses.push(Clause::Where(parse_expr(lexer)))
      continue
    }
    if lexer.eat_word("unwind") {
      let source = parse_expr(lexer)
      lexer.expect_word("as")
      let name = lexer.take_word("a variable")
      clauses.push(Clause::Unwind(source, name))
      continue
    }
    if lexer.eat_word("with") {
      clauses.push(parse_with(lexer))
      continue
    }
    if lexer.eat_word("return") {
      clauses.push(parse_return(lexer))
      continue
    }
    if lexer.eat_word("create") {
      clauses.push(Clause::Create(parse_pattern(lexer)))
      continue
    }
    raise lexer.fail("a clause")
  }
  { clauses, }
}

///|
fn parse_with(lexer : Lexer) -> Clause raise @pgq.Refused {
  let distinct = lexer.eat_word("distinct")
  let items = parse_items(lexer)
  let sort = parse_sort(lexer)
  let skip = parse_skip(lexer)
  let limit = parse_limit(lexer)
  let filter = if lexer.eat_word("where") {
    Some(parse_expr(lexer))
  } else {
    None
  }
  Clause::With(items, distinct, sort, skip, limit, filter)
}

///|
fn parse_return(lexer : Lexer) -> Clause raise @pgq.Refused {
  let distinct = lexer.eat_word("distinct")
  let items = parse_items(lexer)
  let sort = parse_sort(lexer)
  let skip = parse_skip(lexer)
  let limit = parse_limit(lexer)
  Clause::Return(items, distinct, sort, skip, limit)
}

///|
fn parse_sort(lexer : Lexer) -> Array[SortItem] raise @pgq.Refused {
  let items : Array[SortItem] = []
  if !lexer.eat_word("order") {
    return items
  }
  lexer.expect_word("by")
  while true {
    let expr = parse_expr(lexer)
    let mut descending = false
    if lexer.eat_word("desc") || lexer.eat_word("descending") {
      descending = true
    } else {
      lexer.eat_word("asc") |> ignore
      lexer.eat_word("ascending") |> ignore
    }
    items.push({ expr, descending, })
    if !lexer.eat_symbol(",") {
      break
    }
  }
  items
}

///|
fn parse_skip(lexer : Lexer) -> Expr? raise @pgq.Refused {
  if lexer.eat_word("skip") {
    Some(parse_expr(lexer))
  } else {
    None
  }
}

///|
fn parse_limit(lexer : Lexer) -> Expr? raise @pgq.Refused {
  if lexer.eat_word("limit") {
    Some(parse_expr(lexer))
  } else {
    None
  }
}

///|
fn parse_items(lexer : Lexer) -> Array[Item] raise @pgq.Refused {
  let items : Array[Item] = []
  while true {
    if lexer.eat_symbol("*") {
      items.push({ expr: Expr::Star, name: "*", })
    } else {
      let expr = parse_expr(lexer)
      let item_name = if lexer.eat_word("as") {
        lexer.take_word("an alias")
      } else {
        expr.to_text()
      }
      items.push({ expr, name: item_name, })
    }
    if !lexer.eat_symbol(",") {
      break
    }
  }
  items
}

///|
fn parse_pattern(lexer : Lexer) -> Array[PatternPart] raise @pgq.Refused {
  let parts : Array[PatternPart] = []
  while true {
    parts.push(parse_pattern_part(lexer))
    if !lexer.eat_symbol(",") {
      break
    }
  }
  parts
}

///|
fn parse_pattern_part(lexer : Lexer) -> PatternPart raise @pgq.Refused {
  // `MATCH p = (...)-[...]->(...)` names the walk as a whole.
  let path_variable = match lexer.peek() {
    Word(name) =>
      if lexer.next_is_assignment() {
        lexer.advance()
        lexer.expect_symbol("=")
        Some(name)
      } else {
        None
      }
    _ => None
  }
  let nodes : Array[NodePattern] = [parse_node(lexer)]
  let rels : Array[RelPattern] = []
  while true {
    let rel = parse_relationship(lexer)
    match rel {
      None => break
      Some(rel) => {
        rels.push(rel)
        nodes.push(parse_node(lexer))
      }
    }
  }
  { path_variable, nodes, rels, }
}

///|
fn parse_node(lexer : Lexer) -> NodePattern raise @pgq.Refused {
  lexer.expect_symbol("(")
  let variable = match lexer.peek() {
    Word(name) =>
      if lexer.check_symbol(":") || name == "" {
        None
      } else {
        lexer.advance()
        Some(name)
      }
    _ => None
  }
  let labels : Array[String] = []
  while lexer.eat_symbol(":") {
    labels.push(lexer.take_word("a label"))
  }
  let properties = parse_properties(lexer)
  lexer.expect_symbol(")")
  { variable, labels, properties, }
}

///|
fn parse_properties(lexer : Lexer) -> Array[(String, Expr)] raise @pgq.Refused {
  let entries : Array[(String, Expr)] = []
  if !lexer.eat_symbol("{") {
    return entries
  }
  if lexer.eat_symbol("}") {
    return entries
  }
  while true {
    let key = lexer.take_word("a property name")
    lexer.expect_symbol(":")
    entries.push((key, parse_expr(lexer)))
    if !lexer.eat_symbol(",") {
      break
    }
  }
  lexer.expect_symbol("}")
  entries
}

///|
/// Reads a relationship pattern, or nothing when the next token does not start
/// one.
fn parse_relationship(lexer : Lexer) -> RelPattern? raise @pgq.Refused {
  let mut from_left = false
  if lexer.check_symbol("<") {
    lexer.advance()
    lexer.expect_symbol("-")
    from_left = true
  } else if !lexer.eat_symbol("-") {
    return None
  }
  let mut direction = Direction::Both
  let mut variable : String? = None
  let types : Array[String] = []
  let mut min_hops = 1
  let mut max_hops = 1
  let mut properties : Array[(String, Expr)] = []
  if lexer.eat_symbol("[") {
    match lexer.peek() {
      Word(name) =>
        if !lexer.check_symbol(":") && !lexer.check_symbol("]") {
          lexer.advance()
          variable = Some(name)
        }
      _ => ()
    }
    if lexer.eat_symbol(":") {
      while true {
        types.push(lexer.take_word("a relationship type"))
        if !lexer.eat_symbol("|") {
          break
        }
        // A relationship type alternative may keep its colon.
        lexer.eat_symbol(":") |> ignore
      }
    }
    if lexer.eat_symbol("*") {
      min_hops = 1
      max_hops = 64
      match lexer.peek() {
        Number(value, _) => {
          lexer.advance()
          min_hops = value.to_int()
          max_hops = min_hops
          if lexer.eat_symbol("..") {
            match lexer.peek() {
              Number(high, _) => {
                lexer.advance()
                max_hops = high.to_int()
              }
              _ => max_hops = 64
            }
          }
        }
        Symbol(".") => {
          lexer.advance()
          lexer.expect_symbol(".")
          match lexer.peek() {
            Number(high, _) => {
              lexer.advance()
              max_hops = high.to_int()
            }
            _ => max_hops = 64
          }
          min_hops = 1
        }
        _ => ()
      }
    }
    properties = parse_properties(lexer)
    lexer.expect_symbol("]")
  }
  lexer.expect_symbol("-")
  let to_right = lexer.eat_symbol(">")
  // The arrows decide the direction: `->` walks out, `<-` walks in, and a
  // relationship written with neither is followed both ways.
  direction = if from_left && to_right {
    Direction::Both
  } else if from_left {
    Direction::In
  } else if to_right {
    Direction::Out
  } else {
    Direction::Both
  }
  Some({ variable, types, direction, min_hops, max_hops, properties, })
}

///|
fn parse_expr(lexer : Lexer) -> Expr raise @pgq.Refused {
  parse_or(lexer)
}

///|
fn parse_or(lexer : Lexer) -> Expr raise @pgq.Refused {
  let mut left = parse_xor(lexer)
  while lexer.eat_word("or") {
    left = Expr::Binary("OR", left, parse_xor(lexer))
  }
  left
}

///|
fn parse_xor(lexer : Lexer) -> Expr raise @pgq.Refused {
  let mut left = parse_and(lexer)
  while lexer.eat_word("xor") {
    left = Expr::Binary("XOR", left, parse_and(lexer))
  }
  left
}

///|
fn parse_and(lexer : Lexer) -> Expr raise @pgq.Refused {
  let mut left = parse_not(lexer)
  while lexer.eat_word("and") {
    left = Expr::Binary("AND", left, parse_not(lexer))
  }
  left
}

///|
fn parse_not(lexer : Lexer) -> Expr raise @pgq.Refused {
  if lexer.eat_word("not") {
    return Expr::Unary("NOT", parse_not(lexer))
  }
  parse_comparison(lexer)
}

///|
fn parse_comparison(lexer : Lexer) -> Expr raise @pgq.Refused {
  let mut left = parse_additive(lexer)
  while true {
    if lexer.check_word("is") {
      lexer.advance()
      let negated = lexer.eat_word("not")
      lexer.expect_word("null")
      left = Expr::IsNull(left, negated)
      continue
    }
    if lexer.eat_word("in") {
      left = Expr::Binary("IN", left, parse_additive(lexer))
      continue
    }
    if lexer.eat_word("starts") {
      lexer.expect_word("with")
      left = Expr::Binary("STARTS WITH", left, parse_additive(lexer))
      continue
    }
    if lexer.eat_word("ends") {
      lexer.expect_word("with")
      left = Expr::Binary("ENDS WITH", left, parse_additive(lexer))
      continue
    }
    if lexer.eat_word("contains") {
      left = Expr::Binary("CONTAINS", left, parse_additive(lexer))
      continue
    }
    match lexer.peek() {
      Symbol(operator) =>
        match operator {
          "=" | "<>" | "<" | "<=" | ">" | ">=" | "=~" => {
            lexer.advance()
            left = Expr::Binary(operator, left, parse_additive(lexer))
            continue
          }
          _ => break
        }
      _ => break
    }
  }
  left
}

///|
fn parse_additive(lexer : Lexer) -> Expr raise @pgq.Refused {
  let mut left = parse_multiplicative(lexer)
  while true {
    if lexer.eat_symbol("+") {
      left = Expr::Binary("+", left, parse_multiplicative(lexer))
    } else if lexer.eat_symbol("-") {
      left = Expr::Binary("-", left, parse_multiplicative(lexer))
    } else {
      break
    }
  }
  left
}

///|
fn parse_multiplicative(lexer : Lexer) -> Expr raise @pgq.Refused {
  let mut left = parse_power(lexer)
  while true {
    if lexer.eat_symbol("*") {
      left = Expr::Binary("*", left, parse_power(lexer))
    } else if lexer.eat_symbol("/") {
      left = Expr::Binary("/", left, parse_power(lexer))
    } else if lexer.eat_symbol("%") {
      left = Expr::Binary("%", left, parse_power(lexer))
    } else {
      break
    }
  }
  left
}

///|
fn parse_power(lexer : Lexer) -> Expr raise @pgq.Refused {
  let left = parse_unary(lexer)
  if lexer.eat_symbol("^") {
    return Expr::Binary("^", left, parse_power(lexer))
  }
  left
}

///|
fn parse_unary(lexer : Lexer) -> Expr raise @pgq.Refused {
  if lexer.eat_symbol("-") {
    return Expr::Unary("-", parse_unary(lexer))
  }
  if lexer.eat_symbol("+") {
    return parse_unary(lexer)
  }
  parse_postfix(lexer)
}

///|
fn parse_postfix(lexer : Lexer) -> Expr raise @pgq.Refused {
  let mut value = parse_primary(lexer)
  while true {
    if lexer.eat_symbol(".") {
      match lexer.peek() {
        Word(key) => {
          lexer.advance()
          value = Expr::Property(value, key)
        }
        _ => raise lexer.fail("a property name")
      }
      continue
    }
    if lexer.eat_symbol("[") {
      let index = parse_expr(lexer)
      lexer.expect_symbol("]")
      value = Expr::Index(value, index)
      continue
    }
    break
  }
  value
}

///|
fn parse_primary(lexer : Lexer) -> Expr raise @pgq.Refused {
  match lexer.peek() {
    Number(value, raw) => {
      lexer.advance()
      let is_double = raw.contains(".") ||
        raw.contains("e") ||
        raw.contains("E")
      if is_double {
        Expr::Literal(@pgq.Value::Double(value))
      } else {
        Expr::Literal(@pgq.Value::Int(value.to_int64()))
      }
    }
    Text(text) => {
      lexer.advance()
      Expr::Literal(@pgq.Value::Text(text))
    }
    Parameter(name) => {
      lexer.advance()
      Expr::Parameter(name)
    }
    Symbol("(") => {
      lexer.advance()
      let inner = parse_expr(lexer)
      lexer.expect_symbol(")")
      inner
    }
    Symbol("[") => {
      lexer.advance()
      let items : Array[Expr] = []
      if !lexer.eat_symbol("]") {
        while true {
          items.push(parse_expr(lexer))
          if !lexer.eat_symbol(",") {
            break
          }
        }
        lexer.expect_symbol("]")
      }
      Expr::ListLiteral(items)
    }
    Symbol("{") => {
      lexer.advance()
      let entries : Array[(String, Expr)] = []
      if !lexer.eat_symbol("}") {
        while true {
          let key = match lexer.peek() {
            Word(name) => {
              lexer.advance()
              name
            }
            Text(name) => {
              lexer.advance()
              name
            }
            _ => raise lexer.fail("a map key")
          }
          lexer.expect_symbol(":")
          entries.push((key, parse_expr(lexer)))
          if !lexer.eat_symbol(",") {
            break
          }
        }
        lexer.expect_symbol("}")
      }
      Expr::MapLiteral(entries)
    }
    Word(name) => {
      if equal_fold(name, "true") {
        lexer.advance()
        return Expr::Literal(@pgq.Value::Bool(true))
      }
      if equal_fold(name, "false") {
        lexer.advance()
        return Expr::Literal(@pgq.Value::Bool(false))
      }
      if equal_fold(name, "null") {
        lexer.advance()
        return Expr::Literal(@pgq.Value::Nil)
      }
      if equal_fold(name, "case") {
        return parse_case(lexer)
      }
      lexer.advance()
      if lexer.check_symbol("(") {
        lexer.advance()
        let distinct = lexer.eat_word("distinct")
        let args : Array[Expr] = []
        if !lexer.eat_symbol(")") {
          while true {
            if lexer.eat_symbol("*") {
              args.push(Expr::Star)
            } else {
              args.push(parse_expr(lexer))
            }
            if !lexer.eat_symbol(",") {
              break
            }
          }
          lexer.expect_symbol(")")
        }
        return Expr::Call(name, args, distinct)
      }
      Expr::Variable(name)
    }
    _ => raise lexer.fail("an expression")
  }
}

///|
fn parse_case(lexer : Lexer) -> Expr raise @pgq.Refused {
  lexer.expect_word("case")
  let subject : Expr? = if lexer.check_word("when") {
    None
  } else {
    Some(parse_expr(lexer))
  }
  let branches : Array[(Expr, Expr)] = []
  while lexer.eat_word("when") {
    let condition = parse_expr(lexer)
    lexer.expect_word("then")
    let outcome = parse_expr(lexer)
    match subject {
      Some(cond) => branches.push((Expr::Binary("=", cond, condition), outcome))
      None => branches.push((condition, outcome))
    }
  }
  let fallback = if lexer.eat_word("else") {
    Some(parse_expr(lexer))
  } else {
    None
  }
  lexer.expect_word("end")
  Expr::Case(branches, fallback)
}
