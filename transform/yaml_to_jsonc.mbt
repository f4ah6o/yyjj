///|
/// Transform YAML CST to JSONC CST, preserving comments
pub fn yaml_to_jsonc(node : @yaml.YamlNode) -> @jsonc.JsonNode {
  let anchors : Map[String, @yaml.YamlNode] = {}
  transform_yaml_node(node, anchors)
}

///|
fn transform_yaml_node(
  node : @yaml.YamlNode,
  anchors : Map[String, @yaml.YamlNode]
) -> @jsonc.JsonNode {
  let trivia = transform_yaml_trivia(node.trivia())
  match node {
    @yaml.YNull(_) => @jsonc.JsonNode::null_with_trivia(trivia)
    @yaml.YBool(v, _) => @jsonc.JsonNode::bool_with_trivia(v, trivia)
    @yaml.YNumber(n, _) => @jsonc.JsonNode::number_with_trivia(n, trivia)
    @yaml.YString(s, _, _) => @jsonc.JsonNode::string_with_trivia(s, trivia)
    @yaml.YSequence(elements, _) => {
      let json_elements = elements.map(fn(e) { transform_yaml_node(e, anchors) })
      @jsonc.JsonNode::array_with_trivia(json_elements, trivia)
    }
    @yaml.YMapping(pairs, _) => {
      let props = pairs.map(
        fn(p) {
          let key = extract_string_key(p.key)
          let key_trivia = transform_yaml_trivia(p.key_trivia)
          let value = transform_yaml_node(p.value, anchors)
          @jsonc.JProperty::new(key, key_trivia, value)
        },
      )
      @jsonc.JsonNode::object_with_trivia(props, trivia)
    }
    @yaml.YAlias(name, _) => {
      // Look up the anchor and expand it
      match anchors.get(name) {
        Some(anchored_node) => transform_yaml_node(anchored_node, anchors)
        None => {
          // If anchor not found, produce a string with the alias name as fallback
          @jsonc.JsonNode::string_with_trivia("*" + name, trivia)
        }
      }
    }
    @yaml.YAnchor(name, value) => {
      // Register the anchor and transform the value
      anchors.set(name, value)
      transform_yaml_node(value, anchors)
    }
  }
}

///|
fn extract_string_key(node : @yaml.YamlNode) -> String {
  match node {
    @yaml.YString(s, _, _) => s
    @yaml.YNumber(n, _) => n
    @yaml.YBool(true, _) => "true"
    @yaml.YBool(false, _) => "false"
    @yaml.YNull(_) => "null"
    _ => "" // Complex keys are not supported, fallback to empty string
  }
}

///|
fn transform_yaml_trivia(trivia : @common.Trivia) -> @common.Trivia {
  // YAML line comments stay as line comments in JSONC
  // No transformation needed as YAML doesn't have block comments
  trivia
}
