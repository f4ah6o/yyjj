///|
/// Position in source text (0-indexed)
pub struct Pos {
  line : Int
  column : Int
  offset : Int // byte offset from start
} derive(Eq, Show, Arbitrary)

///|
/// Create a new position
pub fn Pos::new(line : Int, column : Int, offset : Int) -> Pos {
  { line, column, offset }
}

///|
/// Initial position (start of file)
pub fn Pos::zero() -> Pos {
  { line: 0, column: 0, offset: 0 }
}

///|
/// Span covering a range in source text
pub struct Span {
  start : Pos
  end : Pos
} derive(Eq, Show, Arbitrary)

///|
/// Create a new span
pub fn Span::new(start : Pos, end : Pos) -> Span {
  { start, end }
}

///|
/// Create an empty span at a position
pub fn Span::at(pos : Pos) -> Span {
  { start: pos, end: pos }
}

///|
/// Merge two spans into one that covers both
pub fn Span::merge(self : Span, other : Span) -> Span {
  let start = if self.start.offset <= other.start.offset {
    self.start
  } else {
    other.start
  }
  let end = if self.end.offset >= other.end.offset {
    self.end
  } else {
    other.end
  }
  { start, end }
}
