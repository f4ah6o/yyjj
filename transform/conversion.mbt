///|
/// Conversion functions with position mapping

///|
/// Convert JSONC to YAML with position mapping
pub fn jsonc_to_yaml_with_mapping(
  input : String
) -> Result[@common.ConversionResult, @common.ParseError] {
  // Parse JSONC
  match @jsonc.parse(input) {
    Ok(jsonc_node) => {
      // Transform to YAML CST
      let yaml_node = jsonc_to_yaml(jsonc_node)

      // Print with tracking (for now, use regular print)
      // In a full implementation, we would track positions during printing
      let output = @yaml.print(yaml_node)

      // For now, create empty mappings
      // TODO: Implement position tracking during printing
      let mappings : Array[@common.SourceMapping] = []

      Ok(@common.ConversionResult::new(output, mappings))
    }
    Err(e) => Err(e)
  }
}

///|
/// Convert YAML to JSONC with position mapping
pub fn yaml_to_jsonc_with_mapping(
  input : String
) -> Result[@common.ConversionResult, @common.ParseError] {
  // Parse YAML
  match @yaml.parse(input) {
    Ok(yaml_node) => {
      // Transform to JSONC CST
      let jsonc_node = yaml_to_jsonc(yaml_node)

      // Print with tracking
      let output = @jsonc.print(jsonc_node)

      // For now, create empty mappings
      // TODO: Implement position tracking during printing
      let mappings : Array[@common.SourceMapping] = []

      Ok(@common.ConversionResult::new(output, mappings))
    }
    Err(e) => Err(e)
  }
}

///|
/// Simplified mapping based on comment positions
/// This creates approximate mappings by correlating comment positions
pub fn create_comment_based_mappings(
  input : String,
  _output : String,
  is_jsonc_input : Bool
) -> Array[@common.SourceMapping] {
  // Extract anchors from input
  let anchors = if is_jsonc_input {
    match @jsonc.parse(input) {
      Ok(node) => extract_jsonc_anchors(node)
      Err(_) => []
    }
  } else {
    match @yaml.parse(input) {
      Ok(node) => extract_yaml_anchors(node)
      Err(_) => []
    }
  }

  // For each anchor (comment span), create a mapping
  // Build array using fold-like approach
  fn build_mappings(index : Int, acc : Array[@common.SourceMapping]) -> Array[@common.SourceMapping] {
    if index >= anchors.length() {
      acc
    } else {
      let anchor = anchors[index]
      let source_start = anchor.span.start
      let source_end = anchor.span.end
      let target_start = @common.Pos::new(
        source_start.line,
        source_start.column,
        source_start.offset,
      )
      let target_end = @common.Pos::new(
        source_end.line,
        source_end.column,
        source_end.offset,
      )
      let mapping = @common.SourceMapping::new(
        source_start,
        source_end,
        target_start,
        target_end,
      )
      build_mappings(index + 1, acc + [mapping])
    }
  }

  build_mappings(0, [])
}
