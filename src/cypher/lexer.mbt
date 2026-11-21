// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One token of a Cypher query. Keywords are recognised by the parser rather
/// than the lexer, so a name that happens to be a keyword is still a name where
/// a name is expected.
pub(all) enum Token {
  Word(String)
  Number(Double, String)
  Text(String)
  Symbol(String)
  Parameter(String)
  End
}

///|
/// A position in the token list.
pub struct Lexer {
  tokens : Array[Token]
  positions : Array[Int32]
  mut at : Int32
}

///|
fn Lexer::of(text : String) -> Lexer raise @pgq.Refused {
  let tokens : Array[Token] = []
  let positions : Array[Int32] = []
  let mut index = 0
  let length = text.length()
  while index < length {
    let ch = text.get_char(index).unwrap_or(' ')
    if ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t' {
      index = index + 1
      continue
    }
    let start = index
    // Comments run to the end of the line.
    if ch == '/' && index + 1 < length && text.get_char(index + 1) == Some('/') {
      while index < length && text.get_char(index) != Some('\n') {
        index = index + 1
      }
      continue
    }
    if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' {
      let buffer = StringBuilder()
      while index < length {
        let inner = text.get_char(index).unwrap_or(' ')
        let continues = (inner >= 'a' && inner <= 'z') ||
          (inner >= 'A' && inner <= 'Z') ||
          (inner >= '0' && inner <= '9') ||
          inner == '_'
        if continues {
          buffer.write_char(inner)
          index = index + 1
        } else {
          break
        }
      }
      tokens.push(Token::Word(buffer.to_string()))
      positions.push(start)
      continue
    }
    if ch >= '0' && ch <= '9' {
      let buffer = StringBuilder()
      let mut seen_point = false
      while index < length {
        let inner = text.get_char(index).unwrap_or(' ')
        if inner >= '0' && inner <= '9' {
          buffer.write_char(inner)
          index = index + 1
        } else if inner == '.' &&
          !seen_point &&
          index + 1 < length &&
          is_digit(text.get_char(index + 1).unwrap_or(' ')) {
          seen_point = true
          buffer.write_char(inner)
          index = index + 1
        } else if (inner == 'e' || inner == 'E') && index + 1 < length {
          buffer.write_char(inner)
          index = index + 1
          let sign = text.get_char(index).unwrap_or(' ')
          if sign == '+' || sign == '-' {
            buffer.write_char(sign)
            index = index + 1
          }
        } else {
          break
        }
      }
      let literal = buffer.to_string()
      tokens.push(Token::Number(parse_decimal(literal), literal))
      positions.push(start)
      continue
    }
    if ch == '\'' || ch == '"' {
      let quote = ch
      index = index + 1
      let buffer = StringBuilder()
      while index < length {
        let inner = text.get_char(index).unwrap_or(' ')
        index = index + 1
        if inner == quote {
          break
        }
        if inner == '\\' && index < length {
          let escaped = text.get_char(index).unwrap_or(' ')
          index = index + 1
          buffer.write_char(
            match escaped {
              'n' => '\n'
              't' => '\t'
              'r' => '\r'
              other => other
            },
          )
        } else {
          buffer.write_char(inner)
        }
      }
      tokens.push(Token::Text(buffer.to_string()))
      positions.push(start)
      continue
    }
    if ch == '$' {
      index = index + 1
      let buffer = StringBuilder()
      while index < length {
        let inner = text.get_char(index).unwrap_or(' ')
        let continues = (inner >= 'a' && inner <= 'z') ||
          (inner >= 'A' && inner <= 'Z') ||
          (inner >= '0' && inner <= '9') ||
          inner == '_'
        if continues {
          buffer.write_char(inner)
          index = index + 1
        } else {
          break
        }
      }
      tokens.push(Token::Parameter(buffer.to_string()))
      positions.push(start)
      continue
    }
    let pair = if index + 1 < length {
      text.exact_view(start=index, end=index + 2).to_owned()
    } else {
      ""
    }
    match pair {
      "<>" | "<=" | ">=" | "=~" | ".." => {
        tokens.push(Token::Symbol(pair))
        positions.push(start)
        index = index + 2
        continue
      }
      _ => ()
    }
    let single = match ch {
      '('
      | ')'
      | '['
      | ']'
      | '{'
      | '}'
      | ','
      | ':'
      | '.'
      | ';'
      | '|'
      | '+'
      | '-'
      | '*'
      | '/'
      | '%'
      | '^'
      | '='
      | '<'
      | '>' => Some(ch)
      _ => None
    }
    match single {
      Some(symbol) => {
        tokens.push(Token::Symbol(symbol.to_string()))
        positions.push(start)
        index = index + 1
      }
      None => raise @pgq.Refused::Malformed(index, ch.to_string(), "a token")
    }
  }
  { tokens, positions, at: 0, }
}

///|
fn is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn parse_decimal(text : String) -> Double {
  let mut total = 0.0
  let mut scale = 1.0
  let mut after_point = false
  let mut exponent = 0
  let mut exponent_sign = 1
  let mut in_exponent = false
  for index in 0..<text.length() {
    let ch = text.get_char(index).unwrap_or(' ')
    if ch == '.' {
      after_point = true
    } else if ch == 'e' || ch == 'E' {
      in_exponent = true
    } else if (ch == '+' || ch == '-') && in_exponent {
      if ch == '-' {
        exponent_sign = -1
      }
    } else if ch >= '0' && ch <= '9' {
      let digit = ch.to_int().to_double() - '0'.to_int().to_double()
      if in_exponent {
        exponent = exponent * 10 + digit.to_int()
      } else if after_point {
        scale = scale / 10.0
        total = total + digit * scale
      } else {
        total = total * 10.0 + digit
      }
    }
  }
  let mut result = total
  for _ in 0..<exponent {
    if exponent_sign > 0 {
      result = result * 10.0
    } else {
      result = result / 10.0
    }
  }
  result
}

///|
fn Lexer::peek(self : Lexer) -> Token {
  match self.tokens.get(self.at) {
    Some(token) => token
    None => Token::End
  }
}

///|
fn Lexer::position(self : Lexer) -> Int32 {
  self.positions.get(self.at).unwrap_or(0)
}

///|
/// True when the token after the next one is `=`, which tells `p = (...)` from
/// a bare pattern.
fn Lexer::next_is_assignment(self : Lexer) -> Bool {
  match self.tokens.get(self.at + 1) {
    Some(Token::Symbol("=")) => true
    _ => false
  }
}

///|
fn Lexer::fail(self : Lexer, want : String) -> @pgq.Refused {
  let found = match self.peek() {
    Word(text) => text
    Number(_, text) => text
    Text(text) => "'" + text + "'"
    Symbol(text) => text
    Parameter(name) => "$" + name
    End => "end of input"
  }
  @pgq.Refused::Malformed(self.position(), found, want)
}

///|
fn Lexer::advance(self : Lexer) -> Unit {
  if self.at < self.tokens.length() {
    self.at = self.at + 1
  }
}

///|
/// True when the next token is the given word, matched without case.
fn Lexer::check_word(self : Lexer, word : String) -> Bool {
  match self.peek() {
    Word(text) => equal_fold(text, word)
    _ => false
  }
}

///|
fn Lexer::eat_word(self : Lexer, word : String) -> Bool {
  if self.check_word(word) {
    self.advance()
    true
  } else {
    false
  }
}

///|
fn Lexer::expect_word(self : Lexer, word : String) -> Unit raise @pgq.Refused {
  if !self.eat_word(word) {
    raise self.fail(word)
  }
}

///|
fn Lexer::check_symbol(self : Lexer, symbol : String) -> Bool {
  match self.peek() {
    Symbol(text) => text == symbol
    _ => false
  }
}

///|
fn Lexer::eat_symbol(self : Lexer, symbol : String) -> Bool {
  if self.check_symbol(symbol) {
    self.advance()
    true
  } else {
    false
  }
}

///|
fn Lexer::expect_symbol(
  self : Lexer,
  symbol : String,
) -> Unit raise @pgq.Refused {
  if !self.eat_symbol(symbol) {
    raise self.fail(symbol)
  }
}

///|
/// A name, which may also be a keyword used as a name.
fn Lexer::take_word(self : Lexer, want : String) -> String raise @pgq.Refused {
  match self.peek() {
    Word(text) => {
      self.advance()
      text
    }
    _ => raise self.fail(want)
  }
}

///|
fn equal_fold(left : String, right : String) -> Bool {
  guard left.length() == right.length() else { return false }
  for index in 0..<left.length() {
    let a = left.get_char(index).unwrap_or(' ')
    let b = right.get_char(index).unwrap_or(' ')
    if fold_char(a) != fold_char(b) {
      return false
    }
  }
  true
}

///|
fn fold_char(ch : Char) -> Char {
  if ch >= 'A' && ch <= 'Z' {
    let offset = ch.to_int() - 'A'.to_int()
    ('a'.to_int() + offset).unsafe_to_char()
  } else {
    ch
  }
}
