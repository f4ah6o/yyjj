///|
/// Comment kind - line or block
pub enum CommentKind {
  LineComment // // or #
  BlockComment // /* */
} derive(Eq, Show, Arbitrary)

///|
/// Create a line comment kind
pub fn CommentKind::line() -> CommentKind {
  LineComment
}

///|
/// Create a block comment kind
pub fn CommentKind::block() -> CommentKind {
  BlockComment
}

///|
/// A single comment token
pub struct Comment {
  content : String // The comment text without delimiters
  kind : CommentKind
  span : Span
  preceding_newline : Bool // Was there a newline before this comment?
} derive(Eq, Show, Arbitrary)

///|
/// Create a new comment
pub fn Comment::new(
  content : String,
  kind : CommentKind,
  span : Span,
  preceding_newline : Bool
) -> Comment {
  { content, kind, span, preceding_newline }
}

///|
/// Trivia attached to a syntax node (comments and whitespace)
pub struct Trivia {
  leading : Array[Comment] // Comments before the node
  trailing : Array[Comment] // Comments on same line after node
} derive(Eq, Show, Arbitrary)

///|
/// Create empty trivia
pub fn Trivia::empty() -> Trivia {
  { leading: [], trailing: [] }
}

///|
/// Create trivia with only leading comments
pub fn Trivia::with_leading(leading : Array[Comment]) -> Trivia {
  { leading, trailing: [] }
}

///|
/// Create trivia with only trailing comments
pub fn Trivia::with_trailing(trailing : Array[Comment]) -> Trivia {
  { leading: [], trailing }
}

///|
/// Create trivia with both leading and trailing comments
pub fn Trivia::new(leading : Array[Comment], trailing : Array[Comment]) -> Trivia {
  { leading, trailing }
}

///|
/// Check if trivia is empty
pub fn Trivia::is_empty(self : Trivia) -> Bool {
  self.leading.is_empty() && self.trailing.is_empty()
}

///|
/// Merge two trivia, combining their comments
pub fn Trivia::merge(self : Trivia, other : Trivia) -> Trivia {
  {
    leading: self.leading + other.leading,
    trailing: self.trailing + other.trailing,
  }
}
