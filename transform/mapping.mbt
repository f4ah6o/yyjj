///|
/// Transform context for tracking position mappings during conversion

///|
/// Context for tracking position mappings during transformation
pub struct TransformContext {
  current_pos : @common.Pos
  mappings : Array[@common.SourceMapping]
}

///|
/// Create a new transform context starting at position zero
pub fn TransformContext::new() -> TransformContext {
  { current_pos: @common.Pos::zero(), mappings: [] }
}

///|
/// Create a new transform context starting at a specific position
pub fn TransformContext::at(start : @common.Pos) -> TransformContext {
  { current_pos: start, mappings: [] }
}

///|
/// Get the current position in the output
pub fn TransformContext::current_position(self : TransformContext) -> @common.Pos {
  self.current_pos
}

///|
/// Get all accumulated mappings
pub fn TransformContext::get_mappings(self : TransformContext) -> Array[@common.SourceMapping] {
  self.mappings
}

///|
/// Update the current position (returns a new context)
pub fn TransformContext::with_position(self : TransformContext, pos : @common.Pos) -> TransformContext {
  { current_pos: pos, mappings: self.mappings }
}

///|
/// Add a mapping from a source span to the current output position (returns a new context)
pub fn TransformContext::with_mapping(
  self : TransformContext,
  source_start : @common.Pos,
  source_end : @common.Pos,
) -> TransformContext {
  let mapping = @common.SourceMapping::new(source_start, source_end, self.current_pos, self.current_pos)
  { current_pos: self.current_pos, mappings: self.mappings + [mapping] }
}

///|
/// Add a complete mapping with both source and target spans (returns a new context)
pub fn TransformContext::with_complete_mapping(
  self : TransformContext,
  source_start : @common.Pos,
  source_end : @common.Pos,
  target_start : @common.Pos,
  target_end : @common.Pos,
) -> TransformContext {
  let mapping = @common.SourceMapping::new(source_start, source_end, target_start, target_end)
  { current_pos: self.current_pos, mappings: self.mappings + [mapping] }
}

///|
/// Advance the current position by a number of characters (returns a new context)
pub fn TransformContext::advanced(self : TransformContext, delta : Int) -> TransformContext {
  let new_pos = @common.Pos::new(
    self.current_pos.line,
    self.current_pos.column + delta,
    self.current_pos.offset + delta,
  )
  { current_pos: new_pos, mappings: self.mappings }
}

///|
/// Advance to a new line (returns a new context)
pub fn TransformContext::advanced_line(self : TransformContext) -> TransformContext {
  let new_pos = @common.Pos::new(
    self.current_pos.line + 1,
    0,
    self.current_pos.offset + 1,
  )
  { current_pos: new_pos, mappings: self.mappings }
}

///|
/// Estimate position advance for a string (handles newlines) - returns a new context
pub fn TransformContext::advanced_by_string(self : TransformContext, s : String) -> TransformContext {
  let mut line = self.current_pos.line
  let mut column = self.current_pos.column
  let mut offset = self.current_pos.offset

  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\n' {
      line = line + 1
      column = 0
    } else {
      column = column + 1
    }
    offset = offset + 1
  }

  let new_pos = @common.Pos::new(line, column, offset)
  { current_pos: new_pos, mappings: self.mappings }
}

///|
/// Create a position with zero values
pub fn pos_zero() -> @common.Pos {
  @common.Pos::zero()
}

///|
/// Create a new position
pub fn pos_new(line : Int, column : Int, offset : Int) -> @common.Pos {
  @common.Pos::new(line, column, offset)
}
