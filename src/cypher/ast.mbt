// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// An expression of a Cypher query.
pub(all) enum Expr {
  Literal(@pgq.Value)
  Variable(String)
  Parameter(String)
  Property(Expr, String)
  Index(Expr, Expr)
  ListLiteral(Array[Expr])
  MapLiteral(Array[(String, Expr)])
  Unary(String, Expr)
  Binary(String, Expr, Expr)
  IsNull(Expr, Bool)
  Call(String, Array[Expr], Bool)
  Case(Array[(Expr, Expr)], Expr?)
  Star
}

///|
/// How a relationship pattern may be walked.
#derive(Eq)
pub(all) enum Direction {
  Out
  In
  Both
}

///|
pub(all) struct NodePattern {
  variable : String?
  labels : Array[String]
  properties : Array[(String, Expr)]
}

///|
pub(all) struct RelPattern {
  variable : String?
  types : Array[String]
  direction : Direction
  /// The shortest and longest number of relationships the pattern stands for.
  min_hops : Int32
  max_hops : Int32
  properties : Array[(String, Expr)]
}

///|
/// A chain of nodes joined by relationships.
pub(all) struct PatternPart {
  /// The name a `MATCH p = ...` gives the whole walk.
  path_variable : String?
  nodes : Array[NodePattern]
  rels : Array[RelPattern]
}

///|
pub(all) struct Item {
  expr : Expr
  name : String
}

///|
pub(all) struct SortItem {
  expr : Expr
  descending : Bool
}

///|
pub(all) enum Clause {
  /// `MATCH` and `OPTIONAL MATCH`, with the filter written after them.
  Match(Array[PatternPart], Bool, Expr?)
  /// `MATCH ... WHERE` as its own clause, which is what a `WHERE` after a
  /// `WITH` becomes.
  Where(Expr)
  With(Array[Item], Bool, Array[SortItem], Expr?, Expr?, Expr?)
  Unwind(Expr, String)
  Return(Array[Item], Bool, Array[SortItem], Expr?, Expr?)
  Create(Array[PatternPart])
}

///|
/// A query: its clauses, in the order they were written.
pub(all) struct Query {
  clauses : Array[Clause]
}

///|
/// What a query returns: named columns and their rows.
pub(all) struct Table {
  columns : Array[String]
  rows : Array[Array[@pgq.Value]]
}

///|
pub fn Table::to_text(self : Table) -> String {
  let lines : Array[String] = [self.columns.join(" | ")]
  for row in self.rows {
    lines.push(row.map(fn(value) { value.to_text() }).join(" | "))
  }
  lines.join("\n")
}

///|
pub fn Expr::to_text(self : Expr) -> String {
  match self {
    Literal(value) => value.to_text()
    Variable(name) => name
    Parameter(name) => "$" + name
    Property(target, key) => target.to_text() + "." + key
    Index(target, index) => target.to_text() + "[" + index.to_text() + "]"
    ListLiteral(items) =>
      "[" + items.map(fn(item) { item.to_text() }).join(", ") + "]"
    MapLiteral(entries) =>
      "{" +
      entries.map(fn(entry) { entry.0 + ": " + entry.1.to_text() }).join(", ") +
      "}"
    Unary(operator, operand) => operator + " " + operand.to_text()
    Binary(operator, left, right) =>
      left.to_text() + " " + operator + " " + right.to_text()
    IsNull(operand, negated) =>
      operand.to_text() + (if negated { " IS NOT NULL" } else { " IS NULL" })
    Call(name, args, distinct) =>
      name +
      "(" +
      (if distinct { "DISTINCT " } else { "" }) +
      args.map(fn(arg) { arg.to_text() }).join(", ") +
      ")"
    Case(_, _) => "CASE"
    Star => "*"
  }
}
