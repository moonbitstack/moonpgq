// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a query was refused: a text that does not parse, a step this engine does
/// not implement, a value of the wrong type, or a write against a read-only
/// store.
pub(all) suberror Refused {
  ///
  /// A parse failure: the offset in the query, what was found there, what was
  /// expected.
  Malformed(Int32, String, String)
  ///
  /// A step or literal the engine does not implement.
  Unsupported(String, String)
  ///
  /// A step was given a value it cannot work with: the step name, what it got,
  /// what it wanted.
  Mismatch(String, String, String)
  ///
  /// A write against a store that does not accept writes.
  NotWritable(String)
}

///|
pub fn Refused::to_text(self : Refused) -> String {
  match self {
    Malformed(at, got, want) =>
      "parse error at " + at.to_string() + ": found " + got + ", wanted " + want
    Unsupported(step, detail) => step + " is not supported: " + detail
    Mismatch(step, got, want) =>
      step + " cannot take " + got + ", wants " + want
    NotWritable(step) => step + " writes, but the store is read-only"
  }
}

///|
pub impl Show for Refused with fn to_string(self) {
  self.to_text()
}
