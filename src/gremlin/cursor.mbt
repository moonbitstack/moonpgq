// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A position in the text being parsed, with the parameters the traversal may
/// refer to by name.
pub struct Parser {
  text : String
  mut at : Int32
  bindings : Array[(String, @pgq.Value)]
}

///|
/// One argument of a step, already resolved to the shape the step wants.
pub(all) enum Arg {
  Value(@pgq.Value)
  Trav(@pgq.Traversal)
  Pred(@pgq.Predicate)
  Order(@pgq.Order)
  Scope(@pgq.Scope)
  Column(@pgq.Column)
  Token(@pgq.Token)
  Pop(@pgq.Pop)
  Cardinality(@pgq.Cardinality)
}

///|
fn Parser::new(text : String, bindings : Array[(String, @pgq.Value)]) -> Parser {
  { text, at: 0, bindings, }
}

///|
/// The character at a position, or the null character past the end. Parsing
/// tests positions against the length first, so the null never reaches a token.
fn char_at(text : String, index : Int32) -> Char {
  text.get_char(index).unwrap_or('\u{0}')
}

///|
fn Parser::fail(self : Parser, want : String) -> @pgq.Refused {
  let rest = if self.at < self.text.length() {
    self.text.exact_view(start=self.at, end=self.at + 1).to_owned()
  } else {
    "end of input"
  }
  @pgq.Refused::Malformed(self.at, rest, want)
}

///|
fn Parser::skip_space(self : Parser) -> Unit {
  while self.at < self.text.length() {
    let ch = char_at(self.text, self.at)
    if ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t' {
      self.at = self.at + 1
    } else {
      break
    }
  }
}

///|
fn Parser::eat(self : Parser, ch : Char) -> Bool {
  self.skip_space()
  if self.at < self.text.length() && char_at(self.text, self.at) == ch {
    self.at = self.at + 1
    return true
  }
  false
}

///|
fn Parser::expect(
  self : Parser,
  ch : Char,
  want : String,
) -> Unit raise @pgq.Refused {
  if !self.eat(ch) {
    raise self.fail(want)
  }
}

///|
fn Parser::at_end(self : Parser) -> Bool {
  self.skip_space()
  self.at >= self.text.length()
}

///|
/// Reads an identifier, or nothing when the next character cannot start one.
fn Parser::ident(self : Parser) -> String? {
  self.skip_space()
  let start = self.at
  while self.at < self.text.length() {
    let ch = char_at(self.text, self.at)
    let continues = (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_'
    if continues {
      self.at = self.at + 1
    } else {
      break
    }
  }
  if self.at == start {
    None
  } else {
    Some(self.text.exact_view(start~, end=self.at).to_owned())
  }
}

///|
/// Reads a quoted string. Both quote characters are accepted; a backslash
/// escapes the next character.
fn Parser::string(self : Parser) -> String? {
  self.skip_space()
  guard self.at < self.text.length() else { return None }
  let quote = char_at(self.text, self.at)
  guard quote == '"' || quote == '\'' else { return None }
  self.at = self.at + 1
  let buffer = StringBuilder()
  while self.at < self.text.length() {
    let ch = char_at(self.text, self.at)
    self.at = self.at + 1
    if ch == quote {
      return Some(buffer.to_string())
    }
    if ch == '\\' && self.at < self.text.length() {
      let escaped = char_at(self.text, self.at)
      self.at = self.at + 1
      buffer.write_char(
        match escaped {
          'n' => '\n'
          't' => '\t'
          'r' => '\r'
          other => other
        },
      )
    } else {
      buffer.write_char(ch)
    }
  }
  None
}

///|
/// Reads a number. A trailing letter picks the width, as Gremlin's literals do:
/// `1` and `1L` are integers, `1.0`, `1.0d` and `1.0f` are doubles.
fn Parser::number(self : Parser) -> @pgq.Value? {
  self.skip_space()
  let start = self.at
  let mut negative = false
  if self.at < self.text.length() && char_at(self.text, self.at) == '-' {
    negative = true
    self.at = self.at + 1
  }
  let mut digits = 0
  let mut is_double = false
  while self.at < self.text.length() {
    let ch = char_at(self.text, self.at)
    if ch >= '0' && ch <= '9' {
      digits = digits + 1
      self.at = self.at + 1
    } else if ch == '.' && !is_double {
      is_double = true
      self.at = self.at + 1
    } else {
      break
    }
  }
  if digits == 0 {
    self.at = start
    return None
  }
  let body_end = self.at
  if self.at < self.text.length() {
    let suffix = char_at(self.text, self.at)
    let is_suffix = suffix == 'L' ||
      suffix == 'l' ||
      suffix == 'd' ||
      suffix == 'D' ||
      suffix == 'f' ||
      suffix == 'F' ||
      suffix == 'i' ||
      suffix == 'I' ||
      suffix == 'b' ||
      suffix == 'B'
    if is_suffix {
      if suffix == 'd' || suffix == 'D' || suffix == 'f' || suffix == 'F' {
        is_double = true
      }
      self.at = self.at + 1
    }
  }
  let body = self.text.exact_view(start~, end=body_end).to_owned()
  let magnitude = if is_double {
    parse_double_text(body)
  } else {
    parse_int_text(body)
  }
  let signed = if negative { -magnitude } else { magnitude }
  if is_double {
    Some(@pgq.Value::Double(signed))
  } else {
    Some(@pgq.Value::Int(signed.to_int64()))
  }
}

///|
fn parse_int_text(text : String) -> Double {
  let mut total = 0.0
  for index in 0..<text.length() {
    let ch = char_at(text, index)
    if ch >= '0' && ch <= '9' {
      total = total * 10.0 +
        (ch.to_int().to_double() - '0'.to_int().to_double())
    }
  }
  total
}

///|
fn parse_double_text(text : String) -> Double {
  let mut total = 0.0
  let mut scale = 1.0
  let mut after_point = false
  for index in 0..<text.length() {
    let ch = char_at(text, index)
    if ch == '.' {
      after_point = true
    } else if ch >= '0' && ch <= '9' {
      let digit = ch.to_int().to_double() - '0'.to_int().to_double()
      if after_point {
        scale = scale / 10.0
        total = total + digit * scale
      } else {
        total = total * 10.0 + digit
      }
    }
  }
  total
}

///|
fn[T] array_find(items : Array[T], accept : (T) -> Bool) -> T? {
  for item in items {
    if accept(item) {
      return Some(item)
    }
  }
  None
}
