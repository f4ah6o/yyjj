///|
/// JSONC Parser - parses tokens into CST with trivia attachment
pub struct Parser {
  tokens : Array[Token]
  mut pos : Int
  pending_trivia : Array[@common.Comment] // Buffer for unattached comments
  mut saw_newline : Bool // Track if we saw a newline since last significant token
}

///|
/// Create a parser from source string
pub fn Parser::from_source(source : String) -> Parser {
  let lexer = Lexer::new(source)
  let tokens = lexer.tokenize()
  { tokens, pos: 0, pending_trivia: [], saw_newline: false }
}

///|
/// Create a parser from tokens
pub fn Parser::new(tokens : Array[Token]) -> Parser {
  { tokens, pos: 0, pending_trivia: [], saw_newline: false }
}

///|
/// Check if at end of input
fn Parser::is_eof(self : Parser) -> Bool {
  self.pos >= self.tokens.length() || self.peek_kind() == Some(Eof)
}

///|
/// Peek current token
fn Parser::peek(self : Parser) -> Token? {
  if self.pos < self.tokens.length() {
    Some(self.tokens[self.pos])
  } else {
    None
  }
}

///|
/// Peek current token kind
fn Parser::peek_kind(self : Parser) -> TokenKind? {
  match self.peek() {
    Some(t) => Some(t.kind)
    None => None
  }
}

///|
/// Advance to next token
fn Parser::advance(self : Parser) -> Token? {
  if self.pos < self.tokens.length() {
    let tok = self.tokens[self.pos]
    self.pos += 1
    Some(tok)
  } else {
    None
  }
}

///|
/// Get current span for error reporting
fn Parser::current_span(self : Parser) -> @common.Span {
  match self.peek() {
    Some(t) => t.span
    None => @common.Span::at(@common.Pos::zero())
  }
}

///|
/// Skip trivia tokens, collecting comments into pending buffer
fn Parser::skip_trivia(self : Parser) -> Unit {
  while true {
    match self.peek_kind() {
      Some(Whitespace(_)) => {
        let _ = self.advance()

      }
      Some(Newline) => {
        let _ = self.advance()
        self.saw_newline = true
      }
      Some(LineComment(content)) => {
        let tok = self.advance()
        guard tok is Some(t) else { return }
        let comment = @common.Comment::new(
          content,
          @common.CommentKind::line(),
          t.span,
          self.saw_newline,
        )
        self.pending_trivia.push(comment)
        self.saw_newline = true // Line comment ends with implicit newline
      }
      Some(BlockComment(content)) => {
        let tok = self.advance()
        guard tok is Some(t) else { return }
        let comment = @common.Comment::new(
          content,
          @common.CommentKind::block(),
          t.span,
          self.saw_newline,
        )
        self.pending_trivia.push(comment)
      }
      _ => break
    }
  }
}

///|
/// Flush pending trivia as leading trivia
fn Parser::flush_leading(self : Parser) -> Array[@common.Comment] {
  let leading = self.pending_trivia.copy()
  self.pending_trivia.clear()
  self.saw_newline = false
  leading
}

///|
/// Collect trailing comments (same line, no preceding newline)
fn Parser::collect_trailing(self : Parser) -> Array[@common.Comment] {
  let trailing : Array[@common.Comment] = []
  while true {
    match self.peek_kind() {
      Some(Whitespace(_)) => {
        let _ = self.advance()

      }
      Some(LineComment(content)) => {
        // Line comment on same line is trailing
        if not(self.saw_newline) {
          let tok = self.advance()
          guard tok is Some(t) else { break }
          let comment = @common.Comment::new(
            content,
            @common.CommentKind::line(),
            t.span,
            false, // No preceding newline for trailing
          )
          trailing.push(comment)
          self.saw_newline = true
        }
        break // Only one trailing comment per node
      }
      Some(BlockComment(content)) => {
        // Block comment on same line is trailing
        if not(self.saw_newline) {
          let tok = self.advance()
          guard tok is Some(t) else { break }
          let comment = @common.Comment::new(
            content,
            @common.CommentKind::block(),
            t.span,
            false,
          )
          trailing.push(comment)
        } else {
          // Put in pending for next node
          let tok = self.advance()
          guard tok is Some(t) else { break }
          let comment = @common.Comment::new(
            content,
            @common.CommentKind::block(),
            t.span,
            self.saw_newline,
          )
          self.pending_trivia.push(comment)
        }
      }
      Some(Newline) => {
        let _ = self.advance()
        self.saw_newline = true
        break
      }
      _ => break
    }
  }
  trailing
}

///|
/// Collect trailing comments after a closing bracket/brace
/// This handles the case where the comment appears on the same line or the next line after ]
fn Parser::collect_trailing_after_bracket(self : Parser) -> Array[@common.Comment] {
  let trailing = self.collect_trailing()
  // After normal trailing collection, check for comments on the next line
  // OR comments immediately after ] (without whitespace)
  while true {
    match self.peek_kind() {
      Some(LineComment(content)) => {
        // Comment on same line (no whitespace before it) or on next line
        let _ = self.advance()
        let comment = @common.Comment::new(
          content,
          @common.CommentKind::line(),
          @common.Span::at(@common.Pos::zero()),
          self.saw_newline,
        )
        trailing.push(comment)
        self.saw_newline = true
        break
      }
      Some(BlockComment(content)) => {
        let _ = self.advance()
        let comment = @common.Comment::new(
          content,
          @common.CommentKind::block(),
          @common.Span::at(@common.Pos::zero()),
          self.saw_newline,
        )
        trailing.push(comment)
        break
      }
      Some(Whitespace(_)) => {
        let _ = self.advance()
      }
      Some(Newline) => {
        let _ = self.advance()
        self.saw_newline = true
        // After newline, check if there's a comment
        match self.peek_kind() {
          Some(LineComment(content)) => {
            let _ = self.advance()
            let comment = @common.Comment::new(
              content,
              @common.CommentKind::line(),
              @common.Span::at(@common.Pos::zero()),
              true, // Preceding newline is true
            )
            trailing.push(comment)
            // Only collect one comment after newline
            break
          }
          Some(BlockComment(content)) => {
            let _ = self.advance()
            let comment = @common.Comment::new(
              content,
              @common.CommentKind::block(),
              @common.Span::at(@common.Pos::zero()),
              true,
            )
            trailing.push(comment)
            break
          }
          _ => break
        }
      }
      _ => break
    }
  }
  trailing
}

///|
/// Expect a specific token kind
fn Parser::expect(
  self : Parser,
  kind : TokenKind
) -> Result[Token, @common.ParseError] {
  self.skip_trivia()
  match self.peek() {
    Some(t) if token_kind_matches(t.kind, kind) => {
      let _ = self.advance()
      Ok(t)
    }
    Some(t) =>
      Err(
        @common.ParseError::unexpected_token(token_kind_name(t.kind), t.span),
      )
    None => Err(@common.ParseError::unexpected_eof(self.current_span()))
  }
}

///|
/// Parse a complete JSONC document
pub fn Parser::parse(self : Parser) -> Result[JsonNode, @common.ParseError] {
  self.skip_trivia()
  let node = match self.parse_value() {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  self.skip_trivia()
  // Check for trailing content
  if not(self.is_eof()) {
    let tok = self.peek()
    guard tok is Some(t) else { return Ok(node) }
    return Err(
      @common.ParseError::new(
        @common.ParseErrorKind::trailing_content(),
        t.span,
        "unexpected content after JSON value",
      ),
    )
  }
  Ok(node)
}

///|
/// Parse any JSON value
fn Parser::parse_value(self : Parser) -> Result[JsonNode, @common.ParseError] {
  self.skip_trivia()
  let leading = self.flush_leading()
  match self.peek_kind() {
    Some(LBrace) => self.parse_object(leading)
    Some(LBracket) => self.parse_array(leading)
    Some(String(s)) => {
      let _ = self.advance()
      let trailing = self.collect_trailing()
      Ok(JString(s, @common.Trivia::new(leading, trailing)))
    }
    Some(Number(n)) => {
      let _ = self.advance()
      let trailing = self.collect_trailing()
      Ok(JNumber(n, @common.Trivia::new(leading, trailing)))
    }
    Some(True) => {
      let _ = self.advance()
      let trailing = self.collect_trailing()
      Ok(JBool(true, @common.Trivia::new(leading, trailing)))
    }
    Some(False) => {
      let _ = self.advance()
      let trailing = self.collect_trailing()
      Ok(JBool(false, @common.Trivia::new(leading, trailing)))
    }
    Some(Null) => {
      let _ = self.advance()
      let trailing = self.collect_trailing()
      Ok(JNull(@common.Trivia::new(leading, trailing)))
    }
    Some(Invalid(msg)) => {
      let span = self.current_span()
      Err(
        @common.ParseError::new(
          @common.ParseErrorKind::unexpected_token(msg),
          span,
          msg,
        ),
      )
    }
    Some(kind) =>
      Err(
        @common.ParseError::unexpected_token(
          token_kind_name(kind),
          self.current_span(),
        ),
      )
    None => Err(@common.ParseError::unexpected_eof(self.current_span()))
  }
}

///|
/// Parse an object
fn Parser::parse_object(
  self : Parser,
  leading : Array[@common.Comment]
) -> Result[JsonNode, @common.ParseError] {
  let _ = self.advance() // consume {
  let properties : Array[JProperty] = []
  self.skip_trivia()
  // Handle empty object
  if self.peek_kind() == Some(RBrace) {
    let _ = self.advance()
    let trailing = self.collect_trailing_after_bracket()
    return Ok(JObject(properties, @common.Trivia::new(leading, trailing)))
  }
  // Parse properties
  while true {
    self.skip_trivia()
    let key_leading = self.flush_leading()
    // Check for trailing comma before closing brace
    if self.peek_kind() == Some(RBrace) {
      break
    }
    // Parse key
    guard self.peek_kind() is Some(String(key)) else {
      return Err(
        @common.ParseError::unexpected_token(
          "expected string key",
          self.current_span(),
        ),
      )
    }
    let _ = self.advance()
    let key_trailing = self.collect_trailing()
    let key_trivia = @common.Trivia::new(key_leading, key_trailing)
    // Expect colon
    self.skip_trivia()
    match self.expect(Colon) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    // Parse value
    let value = match self.parse_value() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    properties.push(JProperty::new(key, key_trivia, value))
    // Check for comma or end
    self.skip_trivia()
    match self.peek_kind() {
      Some(Comma) => {
        let _ = self.advance()

      }
      Some(RBrace) => break
      _ =>
        return Err(
          @common.ParseError::unexpected_token(
            "expected ',' or '}'",
            self.current_span(),
          ),
        )
    }
  }
  // Consume closing brace
  match self.expect(RBrace) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let trailing = self.collect_trailing_after_bracket()
  Ok(JObject(properties, @common.Trivia::new(leading, trailing)))
}

///|
/// Parse an array
fn Parser::parse_array(
  self : Parser,
  leading : Array[@common.Comment]
) -> Result[JsonNode, @common.ParseError] {
  let _ = self.advance() // consume [
  let elements : Array[JsonNode] = []
  self.skip_trivia()
  // Handle empty array
  if self.peek_kind() == Some(RBracket) {
    let _ = self.advance()
    let trailing = self.collect_trailing_after_bracket()
    return Ok(JArray(elements, @common.Trivia::new(leading, trailing)))
  }
  // Parse elements
  while true {
    self.skip_trivia()
    // Check for trailing comma before closing bracket
    if self.peek_kind() == Some(RBracket) {
      break
    }
    // Parse value
    let value = match self.parse_value() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    elements.push(value)
    // Check for comma or end
    self.skip_trivia()
    match self.peek_kind() {
      Some(Comma) => {
        let _ = self.advance()

      }
      Some(RBracket) => break
      _ =>
        return Err(
          @common.ParseError::unexpected_token(
            "expected ',' or ']'",
            self.current_span(),
          ),
        )
    }
  }
  // Consume closing bracket
  match self.expect(RBracket) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let trailing = self.collect_trailing_after_bracket()
  Ok(JArray(elements, @common.Trivia::new(leading, trailing)))
}

// Helper functions

///|
fn token_kind_matches(a : TokenKind, b : TokenKind) -> Bool {
  match (a, b) {
    (LBrace, LBrace) => true
    (RBrace, RBrace) => true
    (LBracket, LBracket) => true
    (RBracket, RBracket) => true
    (Colon, Colon) => true
    (Comma, Comma) => true
    (True, True) => true
    (False, False) => true
    (Null, Null) => true
    (Eof, Eof) => true
    (String(_), String(_)) => true
    (Number(_), Number(_)) => true
    (LineComment(_), LineComment(_)) => true
    (BlockComment(_), BlockComment(_)) => true
    (Whitespace(_), Whitespace(_)) => true
    (Newline, Newline) => true
    (Invalid(_), Invalid(_)) => true
    _ => false
  }
}

///|
fn token_kind_name(kind : TokenKind) -> String {
  match kind {
    LBrace => "'{'"
    RBrace => "'}'"
    LBracket => "'['"
    RBracket => "']'"
    Colon => "':'"
    Comma => "','"
    String(_) => "string"
    Number(_) => "number"
    True => "'true'"
    False => "'false'"
    Null => "'null'"
    LineComment(_) => "comment"
    BlockComment(_) => "comment"
    Whitespace(_) => "whitespace"
    Newline => "newline"
    Eof => "end of input"
    Invalid(msg) => msg
  }
}

///|
/// Convenience function to parse JSONC string
pub fn parse(source : String) -> Result[JsonNode, @common.ParseError] {
  let parser = Parser::from_source(source)
  parser.parse()
}
