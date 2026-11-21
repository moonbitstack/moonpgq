// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn main raise @pgq.Refused {
  let graph = @memory.Store::new()
  @cypher.run(
    graph,
    "CREATE (ada:person {name: 'ada', role: 'engineer'}), " +
    "(bo:person {name: 'bo', role: 'engineer'}), " +
    "(cy:person {name: 'cy', role: 'designer'}), " +
    "(atlas:project {name: 'atlas', year: 2024}), " +
    "(beacon:project {name: 'beacon', year: 2025}), " +
    "(ada)-[:works_on]->(atlas), (bo)-[:works_on]->(atlas), " +
    "(bo)-[:works_on]->(beacon), (cy)-[:works_on]->(beacon)",
  )
  |> ignore
  let by_role = @cypher.run(
    graph,
    "MATCH (p:person)-[:works_on]->(project) " +
    "RETURN p.role AS role, count(DISTINCT project) AS projects " +
    "ORDER BY role",
  )
  println(by_role.to_text())
  let path = @cypher.run(
    graph,
    "MATCH path = (a:person {name: 'cy'})-[:works_on]->(:project)<-[:works_on]-(other) " +
    "RETURN other.name AS colleague, length(path) AS hops",
  )
  println(path.to_text())
}
