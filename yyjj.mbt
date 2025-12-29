///|
/// Convert JSONC string to YAML string, preserving comments
pub fn jsonc_to_yaml(input : String, width? : Int) -> Result[String, @common.ParseError] {
  let parsed = @jsonc.parse(input)
  match parsed {
    Ok(node) => {
      let yaml_node = @transform.jsonc_to_yaml(node)
      let w = width.unwrap_or(80)
      Ok(@yaml.print(yaml_node, width=w))
    }
    Err(e) => Err(e)
  }
}

///|
/// Convert YAML string to JSONC string, preserving comments
pub fn yaml_to_jsonc(input : String, width? : Int) -> Result[String, @common.ParseError] {
  let parsed = @yaml.parse(input)
  match parsed {
    Ok(node) => {
      let jsonc_node = @transform.yaml_to_jsonc(node)
      let w = width.unwrap_or(80)
      Ok(@jsonc.print(jsonc_node, width=w))
    }
    Err(e) => Err(e)
  }
}

///|
/// Parse JSONC string to CST
pub fn parse_jsonc(input : String) -> Result[@jsonc.JsonNode, @common.ParseError] {
  @jsonc.parse(input)
}

///|
/// Parse YAML string to CST
pub fn parse_yaml(input : String) -> Result[@yaml.YamlNode, @common.ParseError] {
  @yaml.parse(input)
}

///|
/// Print JSONC CST to string
pub fn print_jsonc(node : @jsonc.JsonNode, width? : Int) -> String {
  let w = width.unwrap_or(80)
  @jsonc.print(node, width=w)
}

///|
/// Print YAML CST to string
pub fn print_yaml(node : @yaml.YamlNode, width? : Int) -> String {
  let w = width.unwrap_or(80)
  @yaml.print(node, width=w)
}

///|
/// Transform JSONC CST to YAML CST
pub fn transform_jsonc_to_yaml(node : @jsonc.JsonNode) -> @yaml.YamlNode {
  @transform.jsonc_to_yaml(node)
}

///|
/// Transform YAML CST to JSONC CST
pub fn transform_yaml_to_jsonc(node : @yaml.YamlNode) -> @jsonc.JsonNode {
  @transform.yaml_to_jsonc(node)
}

///|
/// Convert JSONC to YAML with position mapping
/// Returns ConversionResult containing output and source mappings
pub fn jsonc_to_yaml_with_mapping(
  input : String
) -> Result[@common.ConversionResult, @common.ParseError] {
  @transform.jsonc_to_yaml_with_mapping(input)
}

///|
/// Convert YAML to JSONC with position mapping
/// Returns ConversionResult containing output and source mappings
pub fn yaml_to_jsonc_with_mapping(
  input : String
) -> Result[@common.ConversionResult, @common.ParseError] {
  @transform.yaml_to_jsonc_with_mapping(input)
}

///|
/// Create position mappings based on comment anchors
/// This is a simplified approach that uses comment positions as reference points
pub fn create_comment_based_mappings(
  input : String,
  output : String,
  is_jsonc_input : Bool
) -> Array[@common.SourceMapping] {
  @transform.create_comment_based_mappings(input, output, is_jsonc_input)
}
