///|
/// YAML token types
pub enum TokenKind {
  // Structural tokens
  Colon // :
  Dash // - (sequence item)
  Comma // , (flow style)
  LBrace // { (flow mapping)
  RBrace // }
  LBracket // [ (flow sequence)
  RBracket // ]
  // Indentation
  Indent(Int) // Increase indent level
  Dedent(Int) // Decrease indent level
  // Scalars
  PlainScalar(String) // unquoted value
  SingleQuotedScalar(String) // 'value'
  DoubleQuotedScalar(String) // "value"
  LiteralBlock(String) // | block
  FoldedBlock(String) // > block
  // Keywords (special values)
  NullValue // null, ~, empty
  TrueValue // true, yes, on
  FalseValue // false, no, off
  // Anchors and aliases
  Anchor(String) // &anchor
  Alias(String) // *alias
  // Comments and whitespace
  Comment(String) // # comment
  Whitespace(String) // spaces (within line)
  Newline // \n or \r\n
  // Special
  DocumentStart // ---
  DocumentEnd // ...
  Eof
  Invalid(String)
} derive(Eq, Show)

///|
/// A token with its span
pub struct Token {
  kind : TokenKind
  span : @common.Span
} derive(Eq, Show)

///|
/// Create a new token
pub fn Token::new(kind : TokenKind, span : @common.Span) -> Token {
  { kind, span }
}

///|
/// Check if token is trivia
pub fn Token::is_trivia(self : Token) -> Bool {
  match self.kind {
    Whitespace(_) | Newline | Comment(_) => true
    _ => false
  }
}

///|
/// Check if token is a comment
pub fn Token::is_comment(self : Token) -> Bool {
  match self.kind {
    Comment(_) => true
    _ => false
  }
}
