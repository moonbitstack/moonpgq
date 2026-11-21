// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The longest walk an unbounded variable-length pattern may take. Cypher's `*`
/// has no upper bound; a graph with a cycle would then never finish, so the
/// engine stops at this length and the caller writes `*1..n` to be explicit.
const MAX_UNBOUNDED_HOPS : Int32 = 8

///|
/// Runs a query and returns its table.
pub fn run(
  graph : &@pgq.Graph,
  text : StringView,
  parameters~ : Array[(String, @pgq.Value)] = [],
) -> Table raise @pgq.Refused {
  let query = parse(text)
  execute(graph, query, parameters~)
}

///|
/// Runs an already parsed query.
pub fn execute(
  graph : &@pgq.Graph,
  query : Query,
  parameters~ : Array[(String, @pgq.Value)] = [],
) -> Table {
  let session : Session = { graph, parameters, }
  let mut rows : Array[Row] = [Row::new()]
  let mut table : Table = { columns: [], rows: [], }
  for clause in query.clauses {
    match clause {
      Match(parts, optional, filter) =>
        rows = match_clause(session, rows, parts, optional, filter)
      Where(expr) =>
        rows = rows.filter(fn(row) { is_true(session.eval(row, expr)) })
      Unwind(source, name) => {
        let next : Array[Row] = []
        for row in rows {
          match session.eval(row, source) {
            @pgq.Value::List(items) =>
              for item in items {
                next.push(row.put(name, item))
              }
            @pgq.Value::Nil => ()
            other => next.push(row.put(name, other))
          }
        }
        rows = next
      }
      With(items, distinct, sort, skip, limit, filter) => {
        let projected = project(session, rows, items, distinct)
        let ordered = sort_rows(session, projected, sort)
        let sliced = slice_rows(session, ordered, skip, limit)
        let kept : Array[Row] = []
        for entry in sliced {
          match filter {
            Some(expr) =>
              if is_true(session.eval(entry.0, expr)) {
                kept.push(entry.0)
              }
            None => kept.push(entry.0)
          }
        }
        rows = kept
      }
      Return(items, distinct, sort, skip, limit) => {
        let projected = project(session, rows, items, distinct)
        let ordered = sort_rows(session, projected, sort)
        let sliced = slice_rows(session, ordered, skip, limit)
        // `RETURN *` names its columns after the variables it carries.
        let columns = if items.any(fn(item) { item.expr is Star }) {
          match sliced.get(0) {
            Some(entry) => entry.0.bindings.map(fn(binding) { binding.0 })
            None => []
          }
        } else {
          items.map(fn(item) { item.name })
        }
        table = {
          columns,
          rows: sliced.map(fn(entry) {
            entry.0.bindings.map(fn(binding) { binding.1 })
          }),
        }
        // A RETURN may be followed by nothing; keep the rows for a uniform loop.
        rows = sliced.map(fn(entry) { entry.0 })
      }
      Create(parts) => rows = create_rows(session, rows, parts)
    }
  }
  table
}

///|
fn is_aggregate(expr : Expr) -> Bool {
  match expr {
    Call(name, _, _) =>
      match name {
        "count" | "sum" | "avg" | "min" | "max" | "collect" => true
        _ => false
      }
    _ => false
  }
}

///|
fn any_aggregate(items : Array[Item]) -> Bool {
  items.any(fn(item) { is_aggregate(item.expr) })
}

///|
/// Projects the rows through the items. With an aggregate among them the rows
/// are grouped by the items that are not aggregates, which is what makes
/// `RETURN n.name, count(*)` mean one row per name.
fn project(
  session : Session,
  rows : Array[Row],
  items : Array[Item],
  distinct : Bool,
) -> Array[(Row, Row)] {
  let out : Array[(Row, Row)] = []
  if any_aggregate(items) {
    let keys : Array[@pgq.Value] = []
    let groups : Array[Array[Row]] = []
    for row in rows {
      let key : Array[@pgq.Value] = []
      for item in items {
        if !is_aggregate(item.expr) {
          key.push(session.eval(row, item.expr))
        }
      }
      match find_group(keys, key) {
        Some(index) => groups[index].push(row)
        None => {
          keys.push(@pgq.Value::List(key))
          groups.push([row])
        }
      }
    }
    if rows.is_empty() && keys.is_empty() {
      // An aggregate over no rows still yields one row, as `count(*)` does.
      let projected : Row = Row::new()
      for item in items {
        let value = if is_aggregate(item.expr) {
          aggregate(session, ([] : Array[Row]), item.expr)
        } else {
          @pgq.Value::Nil
        }
        projected.bindings.push((item.name, value))
      }
      out.push((projected, Row::new()))
      return out
    }
    for index in 0..<groups.length() {
      let members : Array[Row] = groups[index]
      let source : Row = if members.length() > 0 {
        members[0]
      } else {
        Row::new()
      }
      let projected : Row = Row::new()
      for item in items {
        let value = if is_aggregate(item.expr) {
          aggregate(session, members, item.expr)
        } else {
          session.eval(source, item.expr)
        }
        projected.bindings.push((item.name, value))
      }
      out.push((projected, source))
    }
    return if distinct { distinct_entries(out) } else { out }
  }
  for row in rows {
    let projected : Row = Row::new()
    for item in items {
      if item.expr is Star {
        // `RETURN *` carries every binding the row already has.
        for entry in row.bindings {
          projected.bindings.push(entry)
        }
      } else {
        projected.bindings.push((item.name, session.eval(row, item.expr)))
      }
    }
    out.push((projected, row))
  }
  if distinct {
    distinct_entries(out)
  } else {
    out
  }
}

///|
fn find_group(keys : Array[@pgq.Value], key : Array[@pgq.Value]) -> Int32? {
  let wrapped = @pgq.Value::List(key)
  for index in 0..<keys.length() {
    if keys[index].equals(wrapped) {
      return Some(index)
    }
  }
  None
}

///|
fn distinct_entries(entries : Array[(Row, Row)]) -> Array[(Row, Row)] {
  let seen : Array[@pgq.Value] = []
  let out : Array[(Row, Row)] = []
  for entry in entries {
    let key = @pgq.Value::List(entry.0.bindings.map(fn(binding) { binding.1 }))
    if !seen.any(fn(other) { other.equals(key) }) {
      seen.push(key)
      out.push(entry)
    }
  }
  out
}

///|
/// Applies an aggregate to the rows of one group.
fn aggregate(session : Session, rows : Array[Row], expr : Expr) -> @pgq.Value {
  match expr {
    Call(name, args, distinct) => {
      let values : Array[@pgq.Value] = []
      if args.is_empty() || args.get(0) is Some(Star) {
        for _ in rows {
          values.push(@pgq.Value::Int(1L))
        }
      } else {
        for row in rows {
          values.push(session.eval(row, args[0]))
        }
      }
      let kept = values.filter(fn(value) { !(value is @pgq.Value::Nil) })
      let counted = if distinct {
        let unique : Array[@pgq.Value] = []
        for value in kept {
          if !unique.any(fn(other) { other.equals(value) }) {
            unique.push(value)
          }
        }
        unique
      } else {
        kept
      }
      match name {
        "count" => @pgq.Value::Int(counted.length().to_int64())
        "collect" => @pgq.Value::List(counted)
        "sum" => {
          let mut int_total = 0L
          let mut double_total = 0.0
          let mut any_double = false
          for value in counted {
            match value {
              @pgq.Value::Int(number) => {
                int_total = int_total + number
                double_total = double_total + number.to_double()
              }
              @pgq.Value::Double(number) => {
                any_double = true
                double_total = double_total + number
              }
              _ => ()
            }
          }
          if any_double {
            @pgq.Value::Double(double_total)
          } else {
            @pgq.Value::Int(int_total)
          }
        }
        "avg" =>
          if counted.is_empty() {
            @pgq.Value::Nil
          } else {
            let mut total = 0.0
            for value in counted {
              total = total + number_of(value).unwrap_or(0.0)
            }
            @pgq.Value::Double(total / counted.length().to_double())
          }
        "min" => extreme(counted, false)
        "max" => extreme(counted, true)
        _ => @pgq.Value::Nil
      }
    }
    _ => @pgq.Value::Nil
  }
}

///|
fn extreme(values : Array[@pgq.Value], want_max : Bool) -> @pgq.Value {
  let mut best : @pgq.Value = @pgq.Value::Nil
  let mut has = false
  for value in values {
    if !has {
      best = value
      has = true
    } else if want_max {
      if compare_ordered(value, best) > 0 {
        best = value
      }
    } else if compare_ordered(value, best) < 0 {
      best = value
    }
  }
  best
}

///|
/// Sorts projected rows. A sort expression may name an alias of the projection
/// or a variable the row had before it.
fn sort_rows(
  session : Session,
  entries : Array[(Row, Row)],
  sort : Array[SortItem],
) -> Array[(Row, Row)] {
  if sort.is_empty() {
    return entries
  }
  let out = entries.copy()
  out.sort_by(fn(left, right) {
    for item in sort {
      let left_value = evaluate_merged(session, left, item.expr)
      let right_value = evaluate_merged(session, right, item.expr)
      let order = order_of(left_value, right_value)
      if order != 0 {
        return if item.descending { -order } else { order }
      }
    }
    0
  })
  out
}

///|
fn evaluate_merged(
  session : Session,
  entry : (Row, Row),
  expr : Expr,
) -> @pgq.Value {
  session.eval(merged_row(entry), expr)
}

///|
/// A sort expression may read a projected alias and any variable the row had
/// before the projection, so both are visible to it.
fn merged_row(entry : (Row, Row)) -> Row {
  let mut merged = entry.0
  for binding in entry.1.bindings {
    if !merged.has(binding.0) {
      merged = merged.put(binding.0, binding.1)
    }
  }
  merged
}

///|
/// Null sorts after every value in ascending order, which is what openCypher
/// specifies for `ORDER BY`.
fn order_of(left : @pgq.Value, right : @pgq.Value) -> Int32 {
  let left_null = left is @pgq.Value::Nil
  let right_null = right is @pgq.Value::Nil
  if left_null && right_null {
    return 0
  }
  if left_null {
    return 1
  }
  if right_null {
    return -1
  }
  compare_ordered(left, right)
}

///|
fn slice_rows(
  session : Session,
  entries : Array[(Row, Row)],
  skip : Expr?,
  limit : Expr?,
) -> Array[(Row, Row)] {
  let start = match skip {
    Some(expr) =>
      match number_of(session.eval(Row::new(), expr)) {
        Some(value) => value.to_int()
        None => 0
      }
    None => 0
  }
  let count = match limit {
    Some(expr) =>
      match number_of(session.eval(Row::new(), expr)) {
        Some(value) => value.to_int()
        None => entries.length()
      }
    None => entries.length()
  }
  let out : Array[(Row, Row)] = []
  let mut index = start
  let end = start + count
  while index < end && index < entries.length() {
    if index >= 0 {
      out.push(entries[index])
    }
    index = index + 1
  }
  out
}

///|
/// `MATCH` and `OPTIONAL MATCH`.
fn match_clause(
  session : Session,
  rows : Array[Row],
  parts : Array[PatternPart],
  optional : Bool,
  filter : Expr?,
) -> Array[Row] {
  let out : Array[Row] = []
  for row in rows {
    let matched = match_parts(session, row, parts)
    let candidates = if matched.is_empty() && optional {
      [bind_missing(session, row, parts)]
    } else {
      matched
    }
    for candidate in candidates {
      match filter {
        Some(expr) =>
          if is_true(session.eval(candidate, expr)) {
            out.push(candidate)
          }
        None => out.push(candidate)
      }
    }
  }
  out
}

///|
fn match_parts(
  session : Session,
  row : Row,
  parts : Array[PatternPart],
) -> Array[Row] {
  let mut current : Array[Row] = [row]
  for part in parts {
    let next : Array[Row] = []
    for candidate in current {
      for result in match_part(session, candidate, part) {
        next.push(result)
      }
    }
    current = next
  }
  current
}

///|
fn match_part(session : Session, row : Row, part : PatternPart) -> Array[Row] {
  let mut frontier : Array[(Row, @pgq.Value, Array[@pgq.Value])] = []
  for entry in bind_node(session, row, part.nodes[0]) {
    frontier.push((entry.0, entry.1, [entry.1]))
  }
  for index in 0..<part.rels.length() {
    let next : Array[(Row, @pgq.Value, Array[@pgq.Value])] = []
    for entry in frontier {
      for
        walked in walk(
          session,
          entry.0,
          entry.1,
          part.rels[index],
          part.nodes[index + 1],
        ) {
        next.push((walked.0, walked.1, entry.2 + walked.2))
      }
    }
    frontier = next
  }
  let out : Array[Row] = []
  for entry in frontier {
    let bound = match part.path_variable {
      Some(name) => entry.0.put(name, @pgq.Value::Path(@pgq.Path::new(entry.2)))
      None => entry.0
    }
    out.push(bound)
  }
  out
}

///|
/// Binds the first node of a pattern: either the variable already holds a
/// vertex that fits, or every vertex that fits is tried.
fn bind_node(
  session : Session,
  row : Row,
  node : NodePattern,
) -> Array[(Row, @pgq.Value)] {
  match node.variable {
    Some(name) =>
      if row.has(name) {
        return match row.get(name) {
          Some(value) =>
            match value {
              @pgq.Value::Vertex(vertex) =>
                if vertex_fits(session, row, vertex, node) {
                  [(row, value)]
                } else {
                  []
                }
              _ => []
            }
          None => []
        }
      }
    None => ()
  }
  let out : Array[(Row, @pgq.Value)] = []
  for vertex in candidates(session.graph, node.labels) {
    if vertex_fits(session, row, vertex, node) {
      let value = @pgq.Value::Vertex(vertex)
      let bound = match node.variable {
        Some(name) => row.put(name, value)
        None => row
      }
      out.push((bound, value))
    }
  }
  out
}

///|
fn candidates(
  graph : &@pgq.Graph,
  labels : Array[String],
) -> Array[@pgq.Vertex] {
  if labels.is_empty() {
    return graph.vertices().to_array()
  }
  graph.vertices_with_label(labels[0]).to_array()
}

///|
fn vertex_fits(
  session : Session,
  row : Row,
  vertex : @pgq.Vertex,
  node : NodePattern,
) -> Bool {
  for label in node.labels {
    if vertex.label() != label {
      return false
    }
  }
  for property in node.properties {
    let want = session.eval(row, property.1)
    let actual = vertex.property(property.0).unwrap_or(@pgq.Value::Nil)
    if !actual.equals(want) {
      return false
    }
  }
  true
}

///|
/// Walks one relationship pattern from a vertex, binding the relationship and
/// the node it reaches.
fn walk(
  session : Session,
  row : Row,
  from : @pgq.Value,
  rel : RelPattern,
  target : NodePattern,
) -> Array[(Row, @pgq.Value, Array[@pgq.Value])] {
  let vertex = match from {
    @pgq.Value::Vertex(vertex) => vertex
    _ => return []
  }
  let max_hops = if rel.max_hops <= 0 {
    MAX_UNBOUNDED_HOPS
  } else if rel.max_hops == 64 {
    MAX_UNBOUNDED_HOPS
  } else {
    rel.max_hops
  }
  let out : Array[(Row, @pgq.Value, Array[@pgq.Value])] = []
  let mut paths : Array[Array[@pgq.Value]] = [[]]
  let mut frontier : Array[@pgq.Vertex] = [vertex]
  let mut hop = 1
  while hop <= max_hops && !frontier.is_empty() {
    let next_paths : Array[Array[@pgq.Value]] = []
    let next_frontier : Array[@pgq.Vertex] = []
    for index in 0..<frontier.length() {
      let here = frontier[index]
      let base = paths[index]
      for edge in edges_at(session.graph, here.id(), rel.direction) {
        if !rel_fits(session, row, edge, rel) {
          continue
        }
        let reached = match reach(edge, here, rel.direction) {
          Some(vertex) => vertex
          None => continue
        }
        let path = base + [@pgq.Value::Edge(edge)]
        // A variable that is already bound has to reach the same element: the
        // second use of a name joins the pattern, it does not rebind it.
        let bound_match = match target.variable {
          Some(name) =>
            match row.get(name) {
              Some(bound) => id_of(bound).equals(reached.id())
              None => true
            }
          None => true
        }
        if hop >= rel.min_hops &&
          bound_match &&
          vertex_fits(session, row, reached, target) {
          let value = @pgq.Value::Vertex(reached)
          let mut bound = row
          match rel.variable {
            Some(name) =>
              bound = bound.put(
                name,
                if rel.min_hops == 1 && max_hops == 1 {
                  @pgq.Value::Edge(edge)
                } else {
                  @pgq.Value::List(path)
                },
              )
            None => ()
          }
          match target.variable {
            Some(name) => bound = bound.put(name, value)
            None => ()
          }
          out.push((bound, value, path + [value]))
        }
        if hop < max_hops {
          next_paths.push(path)
          next_frontier.push(reached)
        }
      }
    }
    paths = next_paths
    frontier = next_frontier
    hop = hop + 1
  }
  out
}

///|
fn edges_at(
  graph : &@pgq.Graph,
  id : @pgq.Value,
  direction : Direction,
) -> Array[@pgq.Edge] {
  let out : Array[@pgq.Edge] = []
  if direction == Direction::Out || direction == Direction::Both {
    graph.out_edges(id, []).each(fn(edge) { out.push(edge) })
  }
  if direction == Direction::In || direction == Direction::Both {
    graph.in_edges(id, []).each(fn(edge) { out.push(edge) })
  }
  out
}

///|
fn reach(
  edge : @pgq.Edge,
  from : @pgq.Vertex,
  direction : Direction,
) -> @pgq.Vertex? {
  if direction == Direction::Out {
    return edge.in_vertex()
  }
  if direction == Direction::In {
    return edge.out_vertex()
  }
  if edge.out_id().equals(from.id()) {
    edge.in_vertex()
  } else {
    edge.out_vertex()
  }
}

///|
fn rel_fits(
  session : Session,
  row : Row,
  edge : @pgq.Edge,
  rel : RelPattern,
) -> Bool {
  if !rel.types.is_empty() && !rel.types.contains(edge.label()) {
    return false
  }
  for property in rel.properties {
    let want = session.eval(row, property.1)
    let actual = edge.property(property.0).unwrap_or(@pgq.Value::Nil)
    if !actual.equals(want) {
      return false
    }
  }
  true
}

///|
/// The row an `OPTIONAL MATCH` keeps when the pattern found nothing: its new
/// variables are null.
fn bind_missing(
  _session : Session,
  row : Row,
  parts : Array[PatternPart],
) -> Row {
  let mut out = row
  for part in parts {
    for node in part.nodes {
      match node.variable {
        Some(name) => if !out.has(name) { out = out.put(name, @pgq.Value::Nil) }
        None => ()
      }
    }
    for rel in part.rels {
      match rel.variable {
        Some(name) => if !out.has(name) { out = out.put(name, @pgq.Value::Nil) }
        None => ()
      }
    }
  }
  out
}

///|
/// `CREATE`: builds the pattern for each row and binds the variables it names.
fn create_rows(
  session : Session,
  rows : Array[Row],
  parts : Array[PatternPart],
) -> Array[Row] {
  let out : Array[Row] = []
  for row in rows {
    let mut current = row
    for part in parts {
      current = create_part(session, current, part)
    }
    out.push(current)
  }
  out
}

///|
fn create_part(session : Session, row : Row, part : PatternPart) -> Row {
  let mut current = row
  let mut previous : @pgq.Value? = None
  for index in 0..<part.nodes.length() {
    let node = part.nodes[index]
    let value = match node.variable {
      Some(name) =>
        match current.get(name) {
          Some(existing) => existing
          None => {
            let created = create_node(session, current, node)
            current = current.put(name, created)
            created
          }
        }
      None => create_node(session, current, node)
    }
    match previous {
      Some(from) => {
        let rel = part.rels[index - 1]
        let label = if rel.types.is_empty() { "" } else { rel.types[0] }
        let edge = session.graph.add_edge(
          id_of(from),
          label,
          id_of(value),
          None,
        )
        for property in rel.properties {
          session.graph.put_property(
            @pgq.Element::Edge(edge),
            property.0,
            session.eval(current, property.1),
          )
        }
        let edge_value = @pgq.Value::Edge(edge)
        match rel.variable {
          Some(name) => current = current.put(name, edge_value)
          None => ()
        }
      }
      None => ()
    }
    previous = Some(value)
  }
  current
}

///|
fn id_of(value : @pgq.Value) -> @pgq.Value {
  match value {
    @pgq.Value::Vertex(vertex) => vertex.id()
    @pgq.Value::Edge(edge) => edge.id()
    _ => @pgq.Value::Nil
  }
}

///|
fn create_node(session : Session, row : Row, node : NodePattern) -> @pgq.Value {
  let label = if node.labels.is_empty() { "" } else { node.labels[0] }
  let vertex = session.graph.add_vertex(label, None)
  for property in node.properties {
    session.graph.put_property(
      @pgq.Element::Vertex(vertex),
      property.0,
      session.eval(row, property.1),
    )
  }
  @pgq.Value::Vertex(vertex)
}
