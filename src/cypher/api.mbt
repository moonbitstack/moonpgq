// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Reads a literal written in a result table: a number, a string, a list or a
/// map. The conformance suite writes its expected values this way.
pub fn parse_value(text : StringView) -> @pgq.Value raise @pgq.Refused {
  let lexer = Lexer::of(text.to_owned())
  let expr = parse_expr(lexer)
  constant_value(expr)
}

///|
/// Evaluates an expression that holds no variables, which is what a literal in
/// a table is.
fn constant_value(expr : Expr) -> @pgq.Value raise @pgq.Refused {
  match expr {
    Literal(value) => value
    ListLiteral(items) =>
      @pgq.Value::List(
        items.map(fn(item) raise @pgq.Refused { constant_value(item) }),
      )
    MapLiteral(entries) =>
      @pgq.Value::Dict(
        entries.map(fn(entry) raise @pgq.Refused {
          (@pgq.Value::Text(entry.0), constant_value(entry.1))
        }),
      )
    Unary("-", operand) =>
      match constant_value(operand) {
        @pgq.Value::Int(number) => @pgq.Value::Int(-number)
        @pgq.Value::Double(number) => @pgq.Value::Double(-number)
        _ => @pgq.Value::Nil
      }
    Binary("+", left, right) =>
      match (constant_value(left), constant_value(right)) {
        (@pgq.Value::Text(a), @pgq.Value::Text(b)) => @pgq.Value::Text(a + b)
        (a, b) => arith(a, b, "+")
      }
    Binary(operator, left, right) =>
      arith(constant_value(left), constant_value(right), operator)
    _ => @pgq.Value::Nil
  }
}

///|
/// Resolves a pattern written in a result table to the value it names: a node,
/// a relationship, or a walk. The cell is a pattern, so it is matched against
/// the graph the way `MATCH` would match it.
pub fn resolve_pattern(
  graph : &@pgq.Graph,
  text : StringView,
) -> @pgq.Value? raise @pgq.Refused {
  let cell = text.to_owned()
  let is_relationship = cell.has_prefix("[")
  let pattern = if cell.has_prefix("<") && cell.has_suffix(">") {
    cell.exact_view(start=1, end=cell.length() - 1).to_owned()
  } else if is_relationship {
    "()" + cell + "()"
  } else {
    cell
  }
  let query = "MATCH __pgq_path = " + pattern + " RETURN __pgq_path"
  let table = run(graph, query)
  let row = match table.rows.get(0) {
    Some(row) => row
    None => return None
  }
  let value = match row.get(0) {
    Some(value) => value
    None => return None
  }
  // A relationship cell names the middle of the two-node walk around it.
  match value {
    @pgq.Value::Path(path) =>
      if is_relationship {
        path.at(1)
      } else if path.size() == 1 {
        path.at(0)
      } else {
        Some(value)
      }
    _ => Some(value)
  }
}

///|
/// True when a value is what a pattern cell of a result table describes: a node
/// with those labels and properties, a relationship with that type, or a walk.
/// A table may hold several nodes that fit the same cell, so the cell is
/// matched rather than resolved to one element.
pub fn matches_pattern(
  graph : &@pgq.Graph,
  text : StringView,
  value : @pgq.Value,
) -> Bool {
  ignore(graph)
  let cell = text.to_owned()
  if cell.has_prefix("<") && cell.has_suffix(">") {
    return match value {
      @pgq.Value::Path(path) =>
        matches_walk(
          cell.exact_view(start=1, end=cell.length() - 1).to_owned(),
          path,
        )
      _ => false
    }
  }
  if cell.has_prefix("[") {
    return match value {
      @pgq.Value::Edge(edge) => relationship_fits(cell, edge)
      _ => false
    }
  }
  if cell.has_prefix("(") {
    return match value {
      @pgq.Value::Vertex(vertex) => node_fits(cell, vertex)
      _ => false
    }
  }
  false
}

///|
fn node_fits(cell : String, vertex : @pgq.Vertex) -> Bool {
  let node = Ok(parse_node(Lexer::of(cell))) catch {
    _ => Err(@pgq.Refused::Malformed(0, cell, "a node pattern"))
  }
  match node {
    Err(_) => false
    Ok(node) => {
      for label in node.labels {
        if vertex.label() != label {
          return false
        }
      }
      for property in node.properties {
        let want = Ok(constant_value(property.1)) catch {
          _ => Err(@pgq.Refused::Malformed(0, cell, "a value"))
        }
        match want {
          Ok(want) =>
            if !vertex
              .property(property.0)
              .unwrap_or(@pgq.Value::Nil)
              .equals(want) {
              return false
            }
          Err(_) => return false
        }
      }
      true
    }
  }
}

///|
fn relationship_fits(cell : String, edge : @pgq.Edge) -> Bool {
  let pattern = "()-" + cell + "-()"
  let rel = try {
    let lexer = Lexer::of(pattern)
    lexer.expect_symbol("(")
    lexer.expect_symbol(")")
    Ok(parse_relationship(lexer))
  } catch {
    _ => Err(@pgq.Refused::Malformed(0, cell, "a relationship pattern"))
  }
  match rel {
    Err(_) => false
    Ok(None) => false
    Ok(Some(rel)) => {
      if !rel.types.is_empty() && !rel.types.contains(edge.label()) {
        return false
      }
      for property in rel.properties {
        let want = Ok(constant_value(property.1)) catch {
          _ => Err(@pgq.Refused::Malformed(0, cell, "a value"))
        }
        match want {
          Ok(want) =>
            if !edge
              .property(property.0)
              .unwrap_or(@pgq.Value::Nil)
              .equals(want) {
              return false
            }
          Err(_) => return false
        }
      }
      true
    }
  }
}

///|
fn matches_walk(cell : String, path : @pgq.Path) -> Bool {
  let parts = Ok(parse_pattern(Lexer::of(cell))) catch {
    _ => Err(@pgq.Refused::Malformed(0, cell, "a path pattern"))
  }
  match parts {
    Err(_) => false
    Ok(parts) => {
      guard parts.length() == 1 else { return false }
      let part = parts[0]
      let objects = path.objects()
      guard objects.length() == part.nodes.length() + part.rels.length() else {
        return false
      }
      let mut index = 0
      for node in part.nodes {
        match objects.get(index) {
          Some(@pgq.Value::Vertex(vertex)) =>
            if !node_fits_node(node, vertex) {
              return false
            }
          _ => return false
        }
        index = index + 1
        if index <= part.rels.length() {
          let rel = part.rels[index - 1]
          match objects.get(index) {
            Some(@pgq.Value::Edge(edge)) =>
              if !rel.types.is_empty() && !rel.types.contains(edge.label()) {
                return false
              }
            _ => return false
          }
          index = index + 1
        }
      }
      true
    }
  }
}

///|
fn node_fits_node(node : NodePattern, vertex : @pgq.Vertex) -> Bool {
  for label in node.labels {
    if vertex.label() != label {
      return false
    }
  }
  for property in node.properties {
    let want = Ok(constant_value(property.1)) catch {
      _ => Err(@pgq.Refused::Malformed(0, vertex.label(), "a value"))
    }
    match want {
      Ok(want) =>
        if !vertex.property(property.0).unwrap_or(@pgq.Value::Nil).equals(want) {
          return false
        }
      Err(_) => return false
    }
  }
  true
}
