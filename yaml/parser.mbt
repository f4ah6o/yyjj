///|
/// YAML Parser - parses tokens into CST with trivia attachment
pub struct Parser {
  tokens : Array[Token]
  mut pos : Int
  pending_trivia : Array[@common.Comment]
  mut saw_newline : Bool
}

///|
pub fn Parser::from_source(source : String) -> Parser {
  let lexer = Lexer::new(source)
  let tokens = lexer.tokenize()
  { tokens, pos: 0, pending_trivia: [], saw_newline: false }
}

///|
pub fn Parser::new(tokens : Array[Token]) -> Parser {
  { tokens, pos: 0, pending_trivia: [], saw_newline: false }
}

///|
fn Parser::is_eof(self : Parser) -> Bool {
  self.pos >= self.tokens.length() || self.peek_kind() == Some(Eof)
}

///|
fn Parser::peek(self : Parser) -> Token? {
  if self.pos < self.tokens.length() {
    Some(self.tokens[self.pos])
  } else {
    None
  }
}

///|
fn Parser::peek_kind(self : Parser) -> TokenKind? {
  match self.peek() {
    Some(t) => Some(t.kind)
    None => None
  }
}

///|
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
fn Parser::current_span(self : Parser) -> @common.Span {
  match self.peek() {
    Some(t) => t.span
    None => @common.Span::at(@common.Pos::zero())
  }
}

///|
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
      Some(Comment(content)) => {
        let tok = self.advance()
        guard tok is Some(t) else { return }
        let comment = @common.Comment::new(
          content,
          @common.CommentKind::line(),
          t.span,
          self.saw_newline,
        )
        self.pending_trivia.push(comment)
        self.saw_newline = true
      }
      Some(Indent(_)) | Some(Dedent(_)) => {
        // Keep indent/dedent tokens for structure
        break
      }
      _ => break
    }
  }
}

///|
fn Parser::flush_leading(self : Parser) -> Array[@common.Comment] {
  let leading = self.pending_trivia.copy()
  self.pending_trivia.clear()
  self.saw_newline = false
  leading
}

///|
fn Parser::collect_trailing(self : Parser) -> Array[@common.Comment] {
  let trailing : Array[@common.Comment] = []
  while true {
    match self.peek_kind() {
      Some(Whitespace(_)) => {
        let _ = self.advance()

      }
      Some(Comment(content)) => {
        if not(self.saw_newline) {
          let tok = self.advance()
          guard tok is Some(t) else { break }
          let comment = @common.Comment::new(
            content,
            @common.CommentKind::line(),
            t.span,
            false,
          )
          trailing.push(comment)
          self.saw_newline = true
        }
        break
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
pub fn Parser::parse(self : Parser) -> Result[YamlNode, @common.ParseError] {
  self.skip_trivia()
  self.parse_value()
}

///|
fn Parser::parse_value(self : Parser) -> Result[YamlNode, @common.ParseError] {
  self.skip_trivia()
  let leading = self.flush_leading()
  match self.peek_kind() {
    // Indent at the start of a value - check if it's a sequence or mapping
    Some(Indent(_)) => {
      // Peek ahead to see if the next non-trivia token is a Dash (sequence)
      let temp_pos = self.pos + 1
      let mut check_pos = temp_pos
      // Skip trivia (whitespace, newlines, comments)
      while check_pos < self.tokens.length() {
        match self.tokens[check_pos].kind {
          Whitespace(_) | Newline | Comment(_) => {
            check_pos = check_pos + 1
          }
          _ => break
        }
      }
      // If we see a Dash after skipping trivia, it's a sequence
      if check_pos < self.tokens.length() && self.tokens[check_pos].kind is Dash {
        // Consume the indent and parse the sequence
        let _ = self.advance()
        self.skip_trivia()
        self.parse_block_sequence(leading)
      } else {
        // Otherwise, it's a mapping
        self.parse_indented_mapping(leading)
      }
    }
    Some(Dash) => self.parse_block_sequence(leading)
    Some(PlainScalar(_)) | Some(SingleQuotedScalar(_)) | Some(DoubleQuotedScalar(_)) =>
      self.parse_scalar_or_mapping(leading)
    // YAML 1.1 keywords can be mapping keys - check for colon after them
    Some(NullValue) => {
      let _ = self.advance()
      // Check if this is a mapping key
      while self.peek_kind() is Some(Whitespace(_)) {
        let _ = self.advance()
      }
      if self.peek_kind() == Some(Colon) {
        self.parse_mapping_with_first_key("null", Plain, leading)
      } else {
        let trailing = self.collect_trailing()
        Ok(YNull(@common.Trivia::new(leading, trailing)))
      }
    }
    Some(TrueValue) => {
      let _ = self.advance()
      // Check if this is a mapping key (e.g., "on:" in GitHub Actions)
      while self.peek_kind() is Some(Whitespace(_)) {
        let _ = self.advance()
      }
      if self.peek_kind() == Some(Colon) {
        self.parse_mapping_with_first_key("true", Plain, leading)
      } else {
        let trailing = self.collect_trailing()
        Ok(YBool(true, @common.Trivia::new(leading, trailing)))
      }
    }
    Some(FalseValue) => {
      let _ = self.advance()
      // Check if this is a mapping key
      while self.peek_kind() is Some(Whitespace(_)) {
        let _ = self.advance()
      }
      if self.peek_kind() == Some(Colon) {
        self.parse_mapping_with_first_key("false", Plain, leading)
      } else {
        let trailing = self.collect_trailing()
        Ok(YBool(false, @common.Trivia::new(leading, trailing)))
      }
    }
    Some(LBracket) => self.parse_flow_sequence(leading)
    Some(LBrace) => self.parse_flow_mapping(leading)
    Some(LiteralBlock(content)) => {
      let _ = self.advance()
      let trailing = self.collect_trailing()
      Ok(YString(content, Literal, @common.Trivia::new(leading, trailing)))
    }
    Some(FoldedBlock(content)) => {
      let _ = self.advance()
      let trailing = self.collect_trailing()
      Ok(YString(content, Folded, @common.Trivia::new(leading, trailing)))
    }
    Some(Anchor(name)) => {
      let _ = self.advance()
      self.skip_trivia()
      let value = match self.parse_value() {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok(YAnchor(name, value))
    }
    Some(Alias(name)) => {
      let _ = self.advance()
      let trailing = self.collect_trailing()
      Ok(YAlias(name, @common.Trivia::new(leading, trailing)))
    }
    Some(Eof) =>
      Ok(YNull(@common.Trivia::new(leading, []))) // Empty document
    // Dedent or Newline without value means implicit null
    Some(Dedent(_)) | Some(Newline) =>
      Ok(YNull(@common.Trivia::new(leading, [])))
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
fn Parser::parse_scalar_or_mapping(
  self : Parser,
  leading : Array[@common.Comment]
) -> Result[YamlNode, @common.ParseError] {
  // Get the scalar value
  let (scalar, style) = match self.peek_kind() {
    Some(PlainScalar(s)) => (s, Plain)
    Some(SingleQuotedScalar(s)) => (s, SingleQuoted)
    Some(DoubleQuotedScalar(s)) => (s, DoubleQuoted)
    _ => return Err(@common.ParseError::unexpected_eof(self.current_span()))
  }
  let _ = self.advance()
  // Check if this is a mapping (followed by colon)
  // Only skip whitespace on the same line, NOT newlines
  // This is critical for multi-key mappings
  while self.peek_kind() is Some(Whitespace(_)) {
    let _ = self.advance()
  }
  if self.peek_kind() == Some(Colon) {
    // This is a mapping
    self.parse_mapping_with_first_key(scalar, style, leading)
  } else {
    // Just a scalar
    let trailing = self.collect_trailing()
    Ok(YString(scalar, style, @common.Trivia::new(leading, trailing)))
  }
}

///|
fn Parser::parse_mapping_with_first_key(
  self : Parser,
  first_key : String,
  key_style : YamlScalarStyle,
  leading : Array[@common.Comment]
) -> Result[YamlNode, @common.ParseError] {
  let pairs : Array[YKeyValue] = []
  let mut key = first_key
  let mut key_style = key_style
  let mut key_leading = leading
  // Track the base indentation level for this mapping
  // If we dedent to or below this level, the mapping is complete
  let mut base_indent : Int = -1  // -1 means not set yet
  let mut loop_iter = 0
  while true {
    loop_iter += 1
    if first_key == "name" || first_key == "true" || first_key == "on" {
      println("parse_mapping_with_first_key loop \{loop_iter}: first_key=\{first_key}, peek=" + debug_token_kind(self.peek_kind()) + ", base_indent=\{base_indent}")
    }
    // Expect colon
    if self.peek_kind() != Some(Colon) {
      break
    }
    let _ = self.advance() // consume :
    let key_trailing = self.collect_trailing()
    let key_trivia = @common.Trivia::new(key_leading, key_trailing)
    let key_node = YString(key, key_style, @common.Trivia::empty())
    // Parse value
    self.skip_trivia()
    // Handle indent for block value
    let has_indent = if self.peek_kind() is Some(Indent(n)) {
      let _ = self.advance()
      if base_indent == -1 {
        base_indent = n
      }
      if first_key == "name" || first_key == "true" || first_key == "on" {
        println("parse_mapping_with_first_key: consumed Indent(\{n}), set base_indent=\{base_indent}, key=\{key}")
      }
      self.skip_trivia()
      true
    } else {
      false
    }

    // Check if there's a key after optional indent (for indented block mapping)
    let has_key_after = if has_indent {
      let temp_pos = self.pos
      // Skip any indent tokens
      while self.peek_kind() is Some(Indent(_)) {
        self.pos += 1
      }
      // Skip trivia
      while self.peek_kind() is Some(Whitespace(_)) {
        self.pos += 1
      }
      let result = is_potential_key(self.peek_kind())
      self.pos = temp_pos
      result
    } else {
      false
    }

    // Debug logging
    if first_key == "name" || first_key == "true" || first_key == "on" {
      println("parse_mapping: key=\{first_key}, has_indent=\{has_indent}, has_key_after=\{has_key_after}, peek_kind=" + debug_token_kind(self.peek_kind()) + ", self.pos=\{self.pos}")
    }

    // If there's no indent and we see a potential key followed by colon,
    // then this key has no value (implicit null) and the next thing is a sibling key
    let value = if not(has_indent) && self.is_sibling_key_ahead() {
      // This is a sibling key, not a value - return null for current key
      if first_key == "name" || first_key == "true" || first_key == "on" {
        println("parse_mapping_with_first_key: sibling key ahead, returning null for key=\{key}")
      }
      YNull(@common.Trivia::empty())
    } else if has_indent && has_key_after {
      // We have an indent followed by a key - this is an indented block mapping
      // Call parse_indented_mapping directly to handle the nested structure
      if first_key == "name" || first_key == "true" || first_key == "on" {
        println("parse_mapping_with_first_key: calling parse_indented_mapping for key=\{key}")
      }
      match self.parse_indented_mapping([]) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
    } else {
      if first_key == "name" || first_key == "true" || first_key == "on" {
        println("parse_mapping_with_first_key: calling parse_value for key=\{key}, has_indent=\{has_indent}, has_key_after=\{has_key_after}")
      }
      match self.parse_value() {
        Ok(v) => {
          if first_key == "name" || first_key == "true" || first_key == "on" {
            println("parse_mapping_with_first_key: parse_value returned for key=\{key}, peek=" + debug_token_kind(self.peek_kind()))
          }
          v
        }
        Err(e) => return Err(e)
      }
    }
    pairs.push(YKeyValue::new(key_node, key_trivia, value))
    // Debug: log after adding each pair
    if first_key == "name" || first_key == "true" || first_key == "on" {
      println("parse_mapping_with_first_key: after adding pair (key=\{key}), pairs.length=\{pairs.length()}, peek=" + debug_token_kind(self.peek_kind()) + ", self.pos=\{self.pos}")
    }
    // Handle dedent - consume child mapping dedents and check for siblings
    self.skip_trivia()
    match self.peek_kind() {
      Some(Dedent(_)) => {
        // Consume dedents at our level
        while self.peek_kind() is Some(Dedent(dn)) {
          // Check if this dedent exits our mapping level
          let exits_level = if base_indent != -1 {
            dn < base_indent
          } else {
            // If base_indent is not set, Dedent(0) means we're at top level
            dn == 0
          }
          if exits_level {
            // Special case: Dedent(0) means we're back at top level
            // If this is a top-level mapping (first_key was parsed at indent 0),
            // consume it and check for more top-level keys
            if dn == 0 {
              let _ = self.advance()
              // Consume any remaining dedents
              while self.peek_kind() is Some(Dedent(_)) {
                let _ = self.advance()
              }
            }
            break
          }
          // Consume this dedent (at or above base indent)
          let _ = self.advance()
        }
        self.skip_trivia()
        let next_kind = self.peek_kind()
        // Debug logging
        if first_key == "name" || first_key == "true" || first_key == "paths" || first_key == "on" {
          println("parse_mapping_with_first_key: after dedent, next_kind=" + debug_token_kind(next_kind) + ", is_potential_key=" + is_potential_key(next_kind).to_string() + ", base_indent=\{base_indent}, first_key=\{first_key}")
        }
        // If we still see a Dedent, break (let parent handle)
        if self.peek_kind() is Some(Dedent(_)) {
          break
        }
        // If no potential key, also break
        if not(is_potential_key(next_kind)) {
          break
        }
        // Otherwise continue the loop to parse the next key
      }
      _ => ()
    }
    // Check for next key
    self.skip_trivia()
    // Debug: log what we see
    if first_key == "name" || first_key == "true" || first_key == "on" {
      println("parse_mapping_with_first_key: checking for next key, peek=" + debug_token_kind(self.peek_kind()) + ", self.pos=\{self.pos}")
    }
    // Handle Indent tokens that might precede sibling keys at the same level
    // This happens when the current key's value is complete and we see another key at the same level
    if self.peek_kind() is Some(Indent(_)) {
      // Check if this Indent is followed by a potential key (sibling at same level)
      // We need to look past the Indent to see what's next
      let temp_pos = self.pos
      let _ = self.advance()  // consume Indent temporarily
      let has_sibling_key = is_potential_key(self.peek_kind())
      self.pos = temp_pos  // restore position
      if has_sibling_key {
        // This Indent precedes a sibling key, consume it and continue
        let _ = self.advance()
        self.skip_trivia()
      }
      // Otherwise, the Indent starts a nested value for a key we haven't seen yet
      // In this case, we've completed this mapping
      if not(has_sibling_key) {
        break
      }
    }
    match self.peek_kind() {
      Some(PlainScalar(s)) => {
        key = s
        key_style = Plain
        key_leading = self.flush_leading()
        let _ = self.advance()
        self.skip_trivia()
      }
      Some(SingleQuotedScalar(s)) => {
        key = s
        key_style = SingleQuoted
        key_leading = self.flush_leading()
        let _ = self.advance()
        self.skip_trivia()
      }
      Some(DoubleQuotedScalar(s)) => {
        key = s
        key_style = DoubleQuoted
        key_leading = self.flush_leading()
        let _ = self.advance()
        self.skip_trivia()
      }
      // YAML 1.1 booleans and null can also be keys (e.g., "on:" in GitHub Actions)
      Some(TrueValue) => {
        key = "true"
        key_style = Plain
        key_leading = self.flush_leading()
        let _ = self.advance()
        self.skip_trivia()
      }
      Some(FalseValue) => {
        key = "false"
        key_style = Plain
        key_leading = self.flush_leading()
        let _ = self.advance()
        self.skip_trivia()
      }
      Some(NullValue) => {
        key = "null"
        key_style = Plain
        key_leading = self.flush_leading()
        let _ = self.advance()
        self.skip_trivia()
      }
      _ => break
    }
  }
  Ok(YMapping(pairs, @common.Trivia::empty()))
}

///|
fn Parser::parse_block_sequence(
  self : Parser,
  leading : Array[@common.Comment]
) -> Result[YamlNode, @common.ParseError] {
  let elements : Array[YamlNode] = []
  // Track the base indent level of this sequence
  // We consume dedents at or below this level, but leave higher-level dedents for the parent
  let mut base_indent : Int = -1
  while self.peek_kind() == Some(Dash) {
    let _ = self.advance() // consume -
    self.skip_trivia()
    // Handle indent - track the base indent level
    if self.peek_kind() is Some(Indent(n)) {
      let _ = self.advance()
      self.skip_trivia()
      if base_indent == -1 {
        base_indent = n
      }
    }
    let elem = match self.parse_value() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    elements.push(elem)
    // Check for dedent - if we see one, the sequence is done
    // Only consume dedents at or below our base indent level
    self.skip_trivia()
    match self.peek_kind() {
      Some(Dedent(n)) => {
        // If base_indent is not set, we haven't parsed any elements yet, so consume the dedent
        // Otherwise, only consume if the dedent level is >= base_indent (i.e., same or deeper level)
        let should_consume = if base_indent == -1 {
          true
        } else {
          n >= base_indent
        }
        if should_consume {
          let _ = self.advance()
        }
        break
      }
      _ => ()
    }
  }
  Ok(YSequence(elements, @common.Trivia::new(leading, [])))
}

///|
fn Parser::parse_flow_sequence(
  self : Parser,
  leading : Array[@common.Comment]
) -> Result[YamlNode, @common.ParseError] {
  let _ = self.advance() // consume [
  let elements : Array[YamlNode] = []
  self.skip_trivia()
  while self.peek_kind() != Some(RBracket) && not(self.is_eof()) {
    let elem = match self.parse_value() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    elements.push(elem)
    self.skip_trivia()
    if self.peek_kind() == Some(Comma) {
      let _ = self.advance()
      self.skip_trivia()
    }
  }
  if self.peek_kind() == Some(RBracket) {
    let _ = self.advance()

  }
  let trailing = self.collect_trailing()
  Ok(YSequence(elements, @common.Trivia::new(leading, trailing)))
}

///|
fn Parser::parse_flow_mapping(
  self : Parser,
  leading : Array[@common.Comment]
) -> Result[YamlNode, @common.ParseError] {
  let _ = self.advance() // consume {
  let pairs : Array[YKeyValue] = []
  self.skip_trivia()
  while self.peek_kind() != Some(RBrace) && not(self.is_eof()) {
    // Parse key
    let (key_str, key_style) = match self.peek_kind() {
      Some(PlainScalar(s)) => {
        let _ = self.advance()
        (s, Plain)
      }
      Some(SingleQuotedScalar(s)) => {
        let _ = self.advance()
        (s, SingleQuoted)
      }
      Some(DoubleQuotedScalar(s)) => {
        let _ = self.advance()
        (s, DoubleQuoted)
      }
      _ => break
    }
    let key_node = YString(key_str, key_style, @common.Trivia::empty())
    self.skip_trivia()
    // Expect colon
    if self.peek_kind() == Some(Colon) {
      let _ = self.advance()

    }
    self.skip_trivia()
    // Parse value
    let value = match self.parse_value() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    pairs.push(YKeyValue::new(key_node, @common.Trivia::empty(), value))
    self.skip_trivia()
    if self.peek_kind() == Some(Comma) {
      let _ = self.advance()
      self.skip_trivia()
    }
  }
  if self.peek_kind() == Some(RBrace) {
    let _ = self.advance()

  }
  let trailing = self.collect_trailing()
  Ok(YMapping(pairs, @common.Trivia::new(leading, trailing)))
}

///|
///|
fn debug_token_kind(kind : TokenKind?) -> String {
  match kind {
    Some(k) => token_kind_name(k)
    None => "None"
  }
}

///|
fn token_kind_name(kind : TokenKind) -> String {
  match kind {
    Colon => "':'"
    Dash => "'-'"
    Comma => "','"
    LBrace => "'{'"
    RBrace => "'}'"
    LBracket => "'['"
    RBracket => "']'"
    Indent(n) => "indent(" + n.to_string() + ")"
    Dedent(n) => "dedent(" + n.to_string() + ")"
    PlainScalar(s) => "scalar: " + s
    SingleQuotedScalar(s) => "'" + s + "'"
    DoubleQuotedScalar(s) => "\"" + s + "\""
    LiteralBlock(_) => "literal block"
    FoldedBlock(_) => "folded block"
    NullValue => "null"
    TrueValue => "true"
    FalseValue => "false"
    Anchor(n) => "&" + n
    Alias(n) => "*" + n
    Comment(_) => "comment"
    Whitespace(_) => "whitespace"
    Newline => "newline"
    DocumentStart => "---"
    DocumentEnd => "..."
    Eof => "end of input"
    Invalid(msg) => msg
  }
}

///|
fn is_potential_key(kind : TokenKind?) -> Bool {
  match kind {
    Some(PlainScalar(_)) | Some(SingleQuotedScalar(_)) | Some(DoubleQuotedScalar(_)) |
    Some(TrueValue) | Some(FalseValue) | Some(NullValue) => true
    _ => false
  }
}

///|
/// Check if the next tokens form a sibling key (scalar/keyword followed by colon)
/// This is used to detect empty values like "workflow_dispatch:" followed by "push:"
fn Parser::is_sibling_key_ahead(self : Parser) -> Bool {
  // Look at current position
  let start_pos = self.pos
  // Check if we have a potential key
  if not(is_potential_key(self.peek_kind())) {
    return false
  }
  // Save position and look ahead
  self.pos += 1
  // Skip whitespace (but not newline)
  while self.peek_kind() is Some(Whitespace(_)) {
    self.pos += 1
  }
  // Check if followed by colon
  let result = self.peek_kind() == Some(Colon)
  // Restore position
  self.pos = start_pos
  result
}

///|
fn Parser::parse_indented_mapping(
  self : Parser,
  leading : Array[@common.Comment]
) -> Result[YamlNode, @common.ParseError] {
  println("parse_indented_mapping: starting... tokens.length=\{self.tokens.length()}, self.pos=\{self.pos}")
  if self.tokens.length() >= 30 && self.tokens.length() <= 60 {
    println("  All tokens: ")
    for i = 0; i < self.tokens.length(); i = i + 1 {
      println("    \{i}: " + self.tokens[i].kind.to_string())
    }
  } else if self.tokens.length() < 25 {
    println("  All tokens: ")
    for i = 0; i < self.tokens.length(); i = i + 1 {
      println("    \{i}: " + self.tokens[i].kind.to_string())
    }
  }
  // Parse an indented block mapping by collecting all keys at this level
  let pairs : Array[YKeyValue] = []
  let mut key = ""
  let mut key_style : YamlScalarStyle = Plain
  let mut key_leading = self.flush_leading()
  let mut base_indent : Int = -1
  // Track the entry position to detect key level
  let entry_pos = self.pos
  // Check if we were entered right after consuming an Indent (from parse_mapping_with_first_key)
  // If so, the key level is that Indent's level - we should exit when we dedent below it
  if entry_pos > 0 {
    match self.tokens[entry_pos - 1].kind {
      Indent(key_level) => {
        // Keys are at key_level - set base_indent to this level
        base_indent = key_level
        println("  parse_indented_mapping: set base_indent=\{base_indent} from entry Indent at pos \{entry_pos - 1}")
      }
      _ => ()
    }
  }
  let mut loop_count = 0

  while true {
    loop_count += 1
    if loop_count > 50 {
      break
    }

    // Check for dedent at caller level before parsing next key
    // This handles the case where a sequence has ended and we see a dedent
    // that returns to a level at or above our base indent
    match self.peek_kind() {
      Some(Dedent(n)) => {
        println("  parse_indented_mapping: loop start - saw dedent n=\{n}, base_indent=\{base_indent}")
        // Exit if base_indent is set and n < base_indent (dedented PAST our level)
        // Or if base_indent is -1 and n == 0 (dedented to top level)
        // If n == base_indent, we're at the SAME level, so sibling keys may exist
        let should_exit = if base_indent != -1 {
          n < base_indent
        } else {
          n == 0
        }
        if should_exit {
          // Consume the dedent and exit
          println("  parse_indented_mapping: early exit due to dedent, n=\{n}, base_indent=\{base_indent}")
          let _ = self.advance()
          break
        }
        // Otherwise, consume the dedent and continue checking for more keys
        println("  parse_indented_mapping: consuming dedent and continuing, n=\{n}, base_indent=\{base_indent}")
        let _ = self.advance()
        self.skip_trivia()
        continue
      }
      _ => ()
    }

    // Get the next key
    match self.peek_kind() {
      Some(Dash) => {
        // After parsing a key-value pair, we might see a dash that starts a sequence
        // This sequence is the value of the PREVIOUS key, not a new key
        // So we should consume it and add it to the previous pair
        if pairs.length() > 0 {
          // The last pair is the one that should have this sequence as its value
          let last_idx = pairs.length() - 1
          let last_key = pairs[last_idx].key
          println("  parse_indented_mapping: Dash handling - before parse_block_sequence, self.pos=\{self.pos}, tokens.length=\{self.tokens.length()}")
          // Parse the sequence
          match self.parse_block_sequence([]) {
            Ok(seq) => {
              // Replace the last pair's value with the sequence
              let new_pair = YKeyValue::new(last_key, pairs[last_idx].key_trivia, seq)
              pairs[last_idx] = new_pair
              println("  parse_indented_mapping: Dash handling - after parse_block_sequence, self.pos=\{self.pos}, peek=" + debug_token_kind(self.peek_kind()))
            }
            Err(e) => return Err(e)
          }
        }
        continue
      }
      Some(PlainScalar(s)) => {
        println("  parse_indented_mapping iter \{loop_count}: PlainScalar(\{s}), self.pos=\{self.pos}")
        key = s
        key_style = Plain
        key_leading = self.flush_leading()
        let _ = self.advance()
        self.skip_trivia()
      }
      Some(SingleQuotedScalar(s)) => {
        println("  parse_indented_mapping iter \{loop_count}: SingleQuotedScalar(\{s})")
        key = s
        key_style = SingleQuoted
        key_leading = self.flush_leading()
        let _ = self.advance()
        self.skip_trivia()
      }
      Some(DoubleQuotedScalar(s)) => {
        println("  parse_indented_mapping iter \{loop_count}: DoubleQuotedScalar(\{s})")
        key = s
        key_style = DoubleQuoted
        key_leading = self.flush_leading()
        let _ = self.advance()
        self.skip_trivia()
      }
      Some(TrueValue) => {
        println("  parse_indented_mapping iter \{loop_count}: TrueValue")
        key = "true"
        key_style = Plain
        key_leading = self.flush_leading()
        let _ = self.advance()
        self.skip_trivia()
      }
      Some(FalseValue) => {
        println("  parse_indented_mapping iter \{loop_count}: FalseValue")
        key = "false"
        key_style = Plain
        key_leading = self.flush_leading()
        let _ = self.advance()
        self.skip_trivia()
      }
      Some(NullValue) => {
        println("  parse_indented_mapping iter \{loop_count}: NullValue")
        key = "null"
        key_style = Plain
        key_leading = self.flush_leading()
        let _ = self.advance()
        self.skip_trivia()
      }
      Some(Indent(_)) => {
        // Indent before a key - consume it and continue
        // This happens when the previous key's value had nested content
        // and we're now at the same level for the next key
        let _ = self.advance()
        self.skip_trivia()
        // Retry getting the key
        continue
      }
      _ => {
        println("  parse_indented_mapping iter \{loop_count}: breaking, peek=" + debug_token_kind(self.peek_kind()))
        break
      }
    }

    // Expect colon
    if self.peek_kind() != Some(Colon) {
      break
    }
    let _ = self.advance()  // consume :

    let key_trailing = self.collect_trailing()
    let key_trivia = @common.Trivia::new(key_leading, key_trailing)
    let key_node = YString(key, key_style, @common.Trivia::empty())

    // Parse value
    self.skip_trivia()

    // Check for indent for nested value
    let has_indent = if self.peek_kind() is Some(Indent(n)) {
      let _ = self.advance()
      if base_indent == -1 {
        base_indent = n
      }
      self.skip_trivia()
      true
    } else {
      false
    }

    // Check for empty value (sibling key ahead)
    let value = if not(has_indent) && self.is_sibling_key_ahead() {
      YNull(@common.Trivia::empty())
    } else {
      if key == "push" {
        println("  parse_indented_mapping: before parse_value for push, self.pos=\{self.pos}, peek=" + debug_token_kind(self.peek_kind()))
      }
      match self.parse_value() {
        Ok(v) => {
          if key == "push" {
            println("  parse_indented_mapping: after parse_value for push, self.pos=\{self.pos}, peek=" + debug_token_kind(self.peek_kind()))
          }
          v
        }
        Err(e) => return Err(e)
      }
    }

    pairs.push(YKeyValue::new(key_node, key_trivia, value))

    // Debug: show what we have after adding this pair
    if key == "push" {
      println("  parse_indented_mapping: after adding push, pairs.length()=\{pairs.length()}")
    }

    // Handle dedents - consume dedents but stop at base_indent level
    // We should NOT consume dedents past our base indent, as those belong to our parent
    self.skip_trivia()

    // Now that the lexer emits dedents one at a time, we only consume ONE dedent
    // The parser will call us again if there are more dedents to handle
    match self.peek_kind() {
      Some(Dedent(n)) => {
        println("  parse_indented_mapping: saw Dedent(\{n}), base_indent=\{base_indent}, key=\{key}")
        // Check if we've exited this mapping:
        // 1. If base_indent is set and n < base_indent, we've dedented PAST our level
        // 2. If base_indent is -1 and n == 0, we've dedented to top level
        // If n == base_indent, we're at the same level, so sibling keys may exist
        let should_exit = if base_indent != -1 {
          n < base_indent
        } else {
          n == 0
        }
        if should_exit {
          // We've dedented back to or past our base indent level
          // Consume the dedent that triggered exit so the parent can see the next token
          println("  parse_indented_mapping: exiting due to dedent (should_exit), key=\{key}, n=\{n}, base_indent=\{base_indent}")
          let _ = self.advance()
          break
        }
        // Otherwise, consume the dedent and check for more keys
        let _ = self.advance()
        self.skip_trivia()
        // Special case: Dedent followed by Indent means we're at the same level
        // and the next key has a nested value. The Indent is for the next key's value,
        // not a child of the current key. Continue to parse the next key.
        if self.peek_kind() is Some(Indent(_)) {
          // Don't consume the indent yet - it will be handled in the next iteration
          // when we check for indent before parsing the value
          continue
        }
        if key == "push" {
          println("  parse_indented_mapping: consumed dedent, peek=" + debug_token_kind(self.peek_kind()))
        }
      }
      Some(Indent(_)) => {
        // We see an indent after parsing the value - this is for a sibling key
        // Consume the indent and continue to parse the next key
        let _ = self.advance()
        self.skip_trivia()
        continue
      }
      _ => ()
    }

    if key == "push" {
      println("  parse_indented_mapping: after dedents, base_indent=\{base_indent}, peek=" + debug_token_kind(self.peek_kind()))
    }

    // Check if there's a potential key to continue
    if not(is_potential_key(self.peek_kind())) {
      if key == "push" {
        println("  parse_indented_mapping: breaking because no potential key, peek=" + debug_token_kind(self.peek_kind()))
      }
      break
    }
    // Otherwise, continue for more keys
  }

  println("  parse_indented_mapping: returning with pairs.length=\{pairs.length()}, self.pos=\{self.pos}, peek=" + debug_token_kind(self.peek_kind()))
  Ok(YMapping(pairs, @common.Trivia::new(leading, [])))
}

///|
pub fn parse(source : String) -> Result[YamlNode, @common.ParseError] {
  let parser = Parser::from_source(source)
  parser.parse()
}
