///|
/// YAML Lexer - tokenizes YAML source with indent tracking
pub struct Lexer {
  source : String
  mut pos : Int
  mut line : Int
  mut column : Int
  indent_stack : Array[Int] // Stack of indent levels
  mut at_line_start : Bool
  mut pending_dedents : Int // Number of dedents to emit
}

///|
/// Create a new lexer
pub fn Lexer::new(source : String) -> Lexer {
  {
    source,
    pos: 0,
    line: 0,
    column: 0,
    indent_stack: [0], // Start with indent level 0
    at_line_start: true,
    pending_dedents: 0,
  }
}

///|
fn Lexer::current_pos(self : Lexer) -> @common.Pos {
  @common.Pos::new(self.line, self.column, self.pos)
}

///|
fn Lexer::is_eof(self : Lexer) -> Bool {
  self.pos >= self.source.length()
}

///|
fn Lexer::char_at(self : Lexer, idx : Int) -> Char {
  Char::from_int(self.source[idx].to_int())
}

///|
fn Lexer::peek(self : Lexer) -> Char? {
  if self.is_eof() {
    None
  } else {
    Some(self.char_at(self.pos))
  }
}

///|
fn Lexer::peek_at(self : Lexer, offset : Int) -> Char? {
  let idx = self.pos + offset
  if idx >= self.source.length() {
    None
  } else {
    Some(self.char_at(idx))
  }
}

///|
fn Lexer::advance(self : Lexer) -> Char? {
  if self.is_eof() {
    return None
  }
  let ch = self.char_at(self.pos)
  self.pos += 1
  if ch == '\n' {
    self.line += 1
    self.column = 0
    self.at_line_start = true
  } else {
    self.column += 1
    if ch != ' ' && ch != '\t' {
      self.at_line_start = false
    }
  }
  Some(ch)
}

///|
fn Lexer::current_indent(self : Lexer) -> Int {
  match self.indent_stack.last() {
    Some(i) => i
    None => 0
  }
}

///|
/// Count leading spaces on current line
fn Lexer::count_spaces(self : Lexer) -> Int {
  let mut count = 0
  let mut idx = self.pos
  while idx < self.source.length() {
    let ch = self.char_at(idx)
    if ch == ' ' {
      count += 1
      idx += 1
    } else {
      break
    }
  }
  count
}

///|
/// Handle indentation at start of line
fn Lexer::handle_indent(self : Lexer) -> Token? {
  if not(self.at_line_start) {
    return None
  }
  let spaces = self.count_spaces()
  let start = self.current_pos()
  // Skip the spaces
  for i = 0; i < spaces; i = i + 1 {
    let _ = self.advance()
  }
  // Mark that we're no longer at line start after processing indentation
  self.at_line_start = false
  let current = self.current_indent()
  if spaces > current {
    // Indent
    self.indent_stack.push(spaces)
    Some(Token::new(Indent(spaces), @common.Span::new(start, self.current_pos())))
  } else if spaces < current {
    // Calculate dedents needed
    while self.current_indent() > spaces {
      self.indent_stack.pop() |> ignore
      self.pending_dedents += 1
    }
    if self.pending_dedents > 0 {
      self.pending_dedents -= 1
      Some(
        Token::new(Dedent(self.current_indent()), @common.Span::at(start)),
      )
    } else {
      None
    }
  } else {
    None
  }
}

///|
pub fn Lexer::next_token(self : Lexer) -> Token {
  // Handle pending dedents first
  if self.pending_dedents > 0 {
    self.pending_dedents -= 1
    return Token::new(
      Dedent(self.current_indent()),
      @common.Span::at(self.current_pos()),
    )
  }
  // Handle indentation at line start
  match self.handle_indent() {
    Some(tok) => return tok
    None => ()
  }
  let start = self.current_pos()
  match self.peek() {
    None => {
      // At EOF, emit dedents for remaining indentation
      if self.indent_stack.length() > 1 {
        self.indent_stack.pop() |> ignore
        return Token::new(Dedent(self.current_indent()), @common.Span::at(start))
      }
      Token::new(Eof, @common.Span::at(start))
    }
    Some(ch) =>
      match ch {
        // Newline
        '\n' => {
          let _ = self.advance()
          Token::new(Newline, @common.Span::new(start, self.current_pos()))
        }
        '\r' => {
          let _ = self.advance()
          if self.peek() == Some('\n') {
            let _ = self.advance()

          }
          Token::new(Newline, @common.Span::new(start, self.current_pos()))
        }
        // Whitespace (within line, not at start)
        ' ' | '\t' => {
          let ws = self.skip_while(fn(c) { c == ' ' || c == '\t' })
          Token::new(Whitespace(ws), @common.Span::new(start, self.current_pos()))
        }
        // Comment
        '#' => {
          let _ = self.advance()
          let content = self.skip_while(fn(c) { c != '\n' && c != '\r' })
          Token::new(Comment(content), @common.Span::new(start, self.current_pos()))
        }
        // Structural
        ':' => {
          let _ = self.advance()
          Token::new(Colon, @common.Span::new(start, self.current_pos()))
        }
        '-' => {
          // Could be sequence dash or part of a number
          if self.peek_at(1) == Some(' ') || self.peek_at(1) == Some('\n') ||
            self.peek_at(1) is None {
            let _ = self.advance()
            Token::new(Dash, @common.Span::new(start, self.current_pos()))
          } else if self.peek_at(1) == Some('-') && self.peek_at(2) == Some('-') {
            // Document start ---
            let _ = self.advance()
            let _ = self.advance()
            let _ = self.advance()
            Token::new(
              DocumentStart,
              @common.Span::new(start, self.current_pos()),
            )
          } else {
            // Negative number or plain scalar
            self.lex_plain_scalar(start)
          }
        }
        '.' =>
          // Document end ...
          if self.peek_at(1) == Some('.') && self.peek_at(2) == Some('.') {
            let _ = self.advance()
            let _ = self.advance()
            let _ = self.advance()
            Token::new(DocumentEnd, @common.Span::new(start, self.current_pos()))
          } else {
            self.lex_plain_scalar(start)
          }
        // Flow style
        '{' => {
          let _ = self.advance()
          Token::new(LBrace, @common.Span::new(start, self.current_pos()))
        }
        '}' => {
          let _ = self.advance()
          Token::new(RBrace, @common.Span::new(start, self.current_pos()))
        }
        '[' => {
          let _ = self.advance()
          Token::new(LBracket, @common.Span::new(start, self.current_pos()))
        }
        ']' => {
          let _ = self.advance()
          Token::new(RBracket, @common.Span::new(start, self.current_pos()))
        }
        ',' => {
          let _ = self.advance()
          Token::new(Comma, @common.Span::new(start, self.current_pos()))
        }
        // Anchor
        '&' => self.lex_anchor(start)
        // Alias
        '*' => self.lex_alias(start)
        // Quoted strings
        '\'' => self.lex_single_quoted(start)
        '"' => self.lex_double_quoted(start)
        // Block scalars
        '|' => self.lex_literal_block(start)
        '>' => self.lex_folded_block(start)
        // Plain scalar or keyword
        _ => self.lex_plain_scalar(start)
      }
  }
}

///|
fn Lexer::skip_while(self : Lexer, pred : (Char) -> Bool) -> String {
  let start = self.pos
  while not(self.is_eof()) && pred(self.char_at(self.pos)) {
    let _ = self.advance()

  }
  self.source.substring(start~, end=self.pos)
}

///|
fn Lexer::lex_anchor(self : Lexer, start : @common.Pos) -> Token {
  let _ = self.advance() // consume &
  let name = self.skip_while(fn(c) { is_anchor_char(c) })
  if name.length() == 0 {
    Token::new(
      Invalid("empty anchor name"),
      @common.Span::new(start, self.current_pos()),
    )
  } else {
    Token::new(Anchor(name), @common.Span::new(start, self.current_pos()))
  }
}

///|
fn Lexer::lex_alias(self : Lexer, start : @common.Pos) -> Token {
  let _ = self.advance() // consume *
  let name = self.skip_while(fn(c) { is_anchor_char(c) })
  if name.length() == 0 {
    Token::new(
      Invalid("empty alias name"),
      @common.Span::new(start, self.current_pos()),
    )
  } else {
    Token::new(Alias(name), @common.Span::new(start, self.current_pos()))
  }
}

///|
fn Lexer::lex_single_quoted(self : Lexer, start : @common.Pos) -> Token {
  let _ = self.advance() // consume '
  let buf = StringBuilder::new()
  while true {
    match self.peek() {
      None =>
        return Token::new(
          Invalid("unclosed single-quoted string"),
          @common.Span::new(start, self.current_pos()),
        )
      Some('\'') => {
        let _ = self.advance()
        // Check for escaped quote ''
        if self.peek() == Some('\'') {
          let _ = self.advance()
          buf.write_char('\'')
        } else {
          break
        }
      }
      Some(ch) => {
        let _ = self.advance()
        buf.write_char(ch)
      }
    }
  }
  Token::new(
    SingleQuotedScalar(buf.to_string()),
    @common.Span::new(start, self.current_pos()),
  )
}

///|
fn Lexer::lex_double_quoted(self : Lexer, start : @common.Pos) -> Token {
  let _ = self.advance() // consume "
  let buf = StringBuilder::new()
  while true {
    match self.peek() {
      None =>
        return Token::new(
          Invalid("unclosed double-quoted string"),
          @common.Span::new(start, self.current_pos()),
        )
      Some('"') => {
        let _ = self.advance()
        break
      }
      Some('\\') => {
        let _ = self.advance()
        match self.peek() {
          None =>
            return Token::new(
              Invalid("unclosed double-quoted string"),
              @common.Span::new(start, self.current_pos()),
            )
          Some(esc) => {
            let _ = self.advance()
            match esc {
              'n' => buf.write_char('\n')
              't' => buf.write_char('\t')
              'r' => buf.write_char('\r')
              '\\' => buf.write_char('\\')
              '"' => buf.write_char('"')
              '0' => buf.write_char('\u0000')
              _ => {
                buf.write_char('\\')
                buf.write_char(esc)
              }
            }
          }
        }
      }
      Some(ch) => {
        let _ = self.advance()
        buf.write_char(ch)
      }
    }
  }
  Token::new(
    DoubleQuotedScalar(buf.to_string()),
    @common.Span::new(start, self.current_pos()),
  )
}

///|
fn Lexer::lex_literal_block(self : Lexer, start : @common.Pos) -> Token {
  let _ = self.advance() // consume |
  // Skip optional indicators and consume until newline
  while self.peek() is Some(c) && c != '\n' && c != '\r' {
    let _ = self.advance()

  }
  if self.peek() is Some('\n' | '\r') {
    let _ = self.advance()
    if self.peek() == Some('\n') {
      let _ = self.advance()

    }
  }
  // Read block content based on indentation
  let block_indent = self.current_indent() + 2 // Default indent increase
  let buf = StringBuilder::new()
  while not(self.is_eof()) {
    let spaces = self.count_spaces()
    if spaces < block_indent && not(is_blank_line(self)) {
      break
    }
    // Skip indent
    for i = 0; i < spaces; i = i + 1 {
      let _ = self.advance()

    }
    // Read line content
    while self.peek() is Some(c) && c != '\n' && c != '\r' {
      let c = self.peek()
      guard c is Some(ch) else { break }
      buf.write_char(ch)
      let _ = self.advance()

    }
    buf.write_char('\n')
    if self.peek() is Some('\n' | '\r') {
      let _ = self.advance()
      if self.peek() == Some('\n') {
        let _ = self.advance()

      }
    }
  }
  Token::new(
    LiteralBlock(buf.to_string()),
    @common.Span::new(start, self.current_pos()),
  )
}

///|
fn Lexer::lex_folded_block(self : Lexer, start : @common.Pos) -> Token {
  let _ = self.advance() // consume >
  // Skip optional indicators and consume until newline
  while self.peek() is Some(c) && c != '\n' && c != '\r' {
    let _ = self.advance()

  }
  if self.peek() is Some('\n' | '\r') {
    let _ = self.advance()
    if self.peek() == Some('\n') {
      let _ = self.advance()

    }
  }
  // Read block content
  let block_indent = self.current_indent() + 2
  let buf = StringBuilder::new()
  let mut first_line = true
  while not(self.is_eof()) {
    let spaces = self.count_spaces()
    if spaces < block_indent && not(is_blank_line(self)) {
      break
    }
    // Skip indent
    for i = 0; i < spaces; i = i + 1 {
      let _ = self.advance()

    }
    if not(first_line) {
      buf.write_char(' ') // Fold newlines to spaces
    }
    first_line = false
    // Read line content
    while self.peek() is Some(c) && c != '\n' && c != '\r' {
      let c = self.peek()
      guard c is Some(ch) else { break }
      buf.write_char(ch)
      let _ = self.advance()

    }
    if self.peek() is Some('\n' | '\r') {
      let _ = self.advance()
      if self.peek() == Some('\n') {
        let _ = self.advance()

      }
    }
  }
  Token::new(
    FoldedBlock(buf.to_string()),
    @common.Span::new(start, self.current_pos()),
  )
}

///|
fn Lexer::lex_plain_scalar(self : Lexer, start : @common.Pos) -> Token {
  let scalar = self.skip_while(fn(c) { is_plain_scalar_char(c) })
  // Check for keywords
  let kind = match scalar {
    "null" | "Null" | "NULL" | "~" => NullValue
    "true" | "True" | "TRUE" | "yes" | "Yes" | "YES" | "on" | "On" | "ON" =>
      TrueValue
    "false" | "False" | "FALSE" | "no" | "No" | "NO" | "off" | "Off" | "OFF" =>
      FalseValue
    _ => PlainScalar(scalar)
  }
  Token::new(kind, @common.Span::new(start, self.current_pos()))
}

///|
pub fn Lexer::tokenize(self : Lexer) -> Array[Token] {
  let tokens : Array[Token] = []
  while true {
    let tok = self.next_token()
    let is_eof = tok.kind == Eof
    tokens.push(tok)
    if is_eof {
      break
    }
  }
  tokens
}

// Helper functions

///|
fn is_anchor_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '-'
}

///|
fn is_plain_scalar_char(c : Char) -> Bool {
  // Plain scalar can contain most chars except flow indicators and newlines
  c != ':' &&
  c != '#' &&
  c != '\n' &&
  c != '\r' &&
  c != '{' &&
  c != '}' &&
  c != '[' &&
  c != ']' &&
  c != ',' &&
  c != ' ' &&
  c != '\t'
}

///|
fn is_blank_line(lexer : Lexer) -> Bool {
  let mut idx = lexer.pos
  while idx < lexer.source.length() {
    let ch = Char::from_int(lexer.source[idx].to_int())
    if ch == '\n' || ch == '\r' {
      return true
    }
    if ch != ' ' && ch != '\t' {
      return false
    }
    idx += 1
  }
  true // EOF counts as blank
}
