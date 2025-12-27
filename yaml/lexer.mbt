///|
/// YAML Lexer - tokenizes YAML source with indent tracking
pub struct Lexer {
  source : String
  mut pos : Int
  mut line : Int
  mut column : Int
  indent_stack : Array[Int] // Stack of indent levels
  mut at_line_start : Bool
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
  self.source[idx].to_int().unsafe_to_char()
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
  let current = self.current_indent()
  if spaces > current {
    // Indent: consume spaces first
    for i = 0; i < spaces; i = i + 1 {
      let _ = self.advance()
    }
    self.indent_stack.push(spaces)
    // Mark that we're no longer at line start after processing indent
    self.at_line_start = false
    Some(Token::new(Indent(spaces), @common.Span::new(start, self.current_pos())))
  } else if spaces < current {
    // Dedent: pop ONE level at a time
    // DON'T consume spaces yet - we may need to emit more dedents
    let _ = self.indent_stack.pop()
    let to_level = self.current_indent()
    // If there are more dedents needed (to_level > spaces), keep at_line_start true
    // so we'll emit another dedent on the next call
    // Only mark as not at line start and consume spaces if we've dedented to or below the target
    if to_level <= spaces {
      // Final dedent: consume the spaces now
      for i = 0; i < spaces; i = i + 1 {
        let _ = self.advance()
      }
      self.at_line_start = false
    }
    // Otherwise, keep at_line_start true for more dedents (don't consume spaces)
    Some(Token::new(Dedent(to_level), @common.Span::at(start)))
  } else {
    // spaces == current, no indent/dedent needed
    // Consume the spaces
    for i = 0; i < spaces; i = i + 1 {
      let _ = self.advance()
    }
    self.at_line_start = false
    None
  }
}

///|
pub fn Lexer::next_token(self : Lexer) -> Token {
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
  // Plain scalars can contain spaces, but end at:
  // - Newline
  // - `: ` (colon + space, key indicator)
  // - ` #` (space + hash, comment)
  // - Flow indicators: { } [ ] ,
  let mut last_non_space_pos = self.pos
  while not(self.is_eof()) {
    let ch = self.char_at(self.pos)
    // Check for terminators
    match ch {
      '\n' | '\r' | '{' | '}' | '[' | ']' | ',' => break
      ':' => {
        // Check if followed by space, newline, or EOF
        if self.peek_at(1) is Some(next) {
          if next == ' ' || next == '\t' || next == '\n' || next == '\r' {
            break
          }
          // Otherwise, : is part of the scalar
          last_non_space_pos = self.pos + 1
          let _ = self.advance()
        } else {
          // EOF after :, colon is part of the scalar
          last_non_space_pos = self.pos + 1
          let _ = self.advance()
        }
      }
      ' ' | '\t' => {
        // Check if followed by # (comment start)
        if self.peek_at(1) == Some('#') {
          break
        }
        // Otherwise, space is part of the scalar
        let _ = self.advance()
      }
      '#' =>
        // # at start of value is a comment
        break
      _ => {
        last_non_space_pos = self.pos + 1
        let _ = self.advance()
      }
    }
  }
  // Get the scalar string (trimmed of trailing whitespace)
  let start_byte = start.offset
  let scalar = self.source.substring(start=start_byte, end=last_non_space_pos)
  // Check for keywords
  let kind : TokenKind = match scalar {
    "null" | "Null" | "NULL" | "~" => NullValue
    "true" | "True" | "TRUE" | "yes" | "Yes" | "YES" | "on" | "On" | "ON" =>
      TrueValue(scalar)
    "false" | "False" | "FALSE" | "no" | "No" | "NO" | "off" | "Off" | "OFF" =>
      FalseValue(scalar)
    _ => PlainScalar(scalar)
  }
  // Reset position to end of trimmed scalar
  self.pos = last_non_space_pos
  // Recalculate line/column
  let mut line = start.line
  let mut col = start.column
  for i = start_byte; i < last_non_space_pos; i = i + 1 {
    if self.source[i].to_int().unsafe_to_char() == '\n' {
      line += 1
      col = 0
    } else {
      col += 1
    }
  }
  self.line = line
  self.column = col
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
fn is_blank_line(lexer : Lexer) -> Bool {
  let mut idx = lexer.pos
  while idx < lexer.source.length() {
    let ch = lexer.source[idx].to_int().unsafe_to_char()
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
