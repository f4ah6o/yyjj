///|
/// Position mapping between source and target during conversion

///|
/// A mapping from a source position range to a target position range
pub struct SourceMapping {
  source_start : Pos
  source_end : Pos
  target_start : Pos
  target_end : Pos
} derive(Eq, Show)

///|
/// Create a new position mapping
pub fn SourceMapping::new(
  source_start : Pos,
  source_end : Pos,
  target_start : Pos,
  target_end : Pos,
) -> SourceMapping {
  { source_start, source_end, target_start, target_end }
}

///|
/// Conversion result with position mappings
pub struct ConversionResult {
  output : String
  mappings : Array[SourceMapping]
} derive(Eq, Show)

///|
/// Create a new conversion result
pub fn ConversionResult::new(
  output : String,
  mappings : Array[SourceMapping],
) -> ConversionResult {
  { output, mappings }
}

///|
/// Empty conversion result
pub fn ConversionResult::empty() -> ConversionResult {
  { output: "", mappings: [] }
}

///|
/// Find the target position for a given source position
/// Returns None if no mapping contains the source position
pub fn lookup_target_position(
  mappings : Array[SourceMapping],
  source_line : Int,
  source_column : Int,
  source_offset : Int,
) -> Option[Pos] {
  for mapping in mappings {
    if position_in_range(
      source_line,
      source_column,
      source_offset,
      mapping.source_start,
      mapping.source_end,
    ) {
      return Some(mapping.target_start)
    }
  }
  None
}

///|
/// Find the source position for a given target position
pub fn lookup_source_position(
  mappings : Array[SourceMapping],
  target_line : Int,
  target_column : Int,
  target_offset : Int,
) -> Option[Pos] {
  for mapping in mappings {
    if position_in_range(
      target_line,
      target_column,
      target_offset,
      mapping.target_start,
      mapping.target_end,
    ) {
      return Some(mapping.source_start)
    }
  }
  None
}

///|
/// Check if a position is within a range (inclusive)
fn position_in_range(
  line : Int,
  column : Int,
  offset : Int,
  range_start : Pos,
  range_end : Pos,
) -> Bool {
  let after_start_offset = offset > range_start.offset
  let after_start_same_offset_line = offset == range_start.offset && line == range_start.line
  let after_start_same_offset_col = after_start_same_offset_line && column >= range_start.column
  let after_start_same_offset_greater_line = offset == range_start.offset && line > range_start.line
  let after_start = after_start_offset || after_start_same_offset_col || after_start_same_offset_greater_line

  let before_end_offset = offset < range_end.offset
  let before_end_same_offset_line = offset == range_end.offset && line == range_end.line
  let before_end_same_offset_col = before_end_same_offset_line && column <= range_end.column
  let before_end_same_offset_less_line = offset == range_end.offset && line < range_end.line
  let before_end = before_end_offset || before_end_same_offset_col || before_end_same_offset_less_line

  if after_start {
    before_end
  } else {
    false
  }
}
