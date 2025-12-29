///|
/// Anchor extraction from CST for position mapping

///|
/// An anchor point in the source - a span with associated value identifier
pub struct Anchor {
  span : Span
  path : Array[String] // JSON path to the value (e.g., ["user", "name"])
  value_kind : String // "string", "number", "bool", "null", "object", "array"
} derive(Eq, Show)

///|
/// Create a new anchor
pub fn Anchor::new(span : Span, path : Array[String], value_kind : String) -> Anchor {
  { span, path, value_kind }
}

///|
/// Extract all anchors from a JSONC CST
pub fn extract_jsonc_anchors(node : @jsonc.JsonNode) -> Array[Anchor] {
  extract_jsonc_anchors_with_path(node, [])
}

///|
/// Extract anchors with current path
fn extract_jsonc_anchors_with_path(
  node : @jsonc.JsonNode,
  path : Array[String]
) -> Array[Anchor] {
  let mut anchors : Array[Anchor] = []

  // Extract spans from trivia as anchors
  let trivia = node.trivia()
  for comment in trivia.leading {
    let anchor = Anchor::new(comment.span, path, value_kind(node))
    anchors.push(anchor)
  }
  for comment in trivia.trailing {
    let anchor = Anchor::new(comment.span, path, value_kind(node))
    anchors.push(anchor)
  }

  // Recursively extract from children
  match node {
    @jsonc.JObject(props, _) => {
      for prop in props {
        let new_path = path + [prop.key]
        let child_anchors = extract_jsonc_anchors_with_path(prop.value, new_path)
        anchors = anchors + child_anchors
      }
    }
    @jsonc.JArray(elements, _) => {
      for i = 0; i < elements.length(); i = i + 1 {
        let new_path = path + [i.to_string()]
        let child_anchors = extract_jsonc_anchors_with_path(elements[i], new_path)
        anchors = anchors + child_anchors
      }
    }
    _ => ()
  }

  anchors
}

///|
/// Get the value kind string for a node
fn value_kind(node : @jsonc.JsonNode) -> String {
  match node {
    @jsonc.JNull(_) => "null"
    @jsonc.JBool(_, _) => "bool"
    @jsonc.JNumber(_, _) => "number"
    @jsonc.JString(_, _) => "string"
    @jsonc.JArray(_, _) => "array"
    @jsonc.JObject(_, _) => "object"
  }
}

///|
/// Extract all anchors from a YAML CST
pub fn extract_yaml_anchors(node : @yaml.YamlNode) -> Array[Anchor] {
  extract_yaml_anchors_with_path(node, [])
}

///|
/// Extract anchors with current path from YAML
fn extract_yaml_anchors_with_path(
  node : @yaml.YamlNode,
  path : Array[String]
) -> Array[Anchor] {
  let mut anchors : Array[Anchor] = []

  // Extract spans from trivia as anchors
  let trivia = node.trivia()
  for comment in trivia.leading {
    let anchor = Anchor::new(comment.span, path, yaml_value_kind(node))
    anchors.push(anchor)
  }
  for comment in trivia.trailing {
    let anchor = Anchor::new(comment.span, path, yaml_value_kind(node))
    anchors.push(anchor)
  }

  // Recursively extract from children
  match node {
    @yaml.YMapping(pairs, _) => {
      for pair in pairs {
        let key = extract_yaml_key(pair.key)
        let new_path = path + [key]
        let child_anchors = extract_yaml_anchors_with_path(pair.value, new_path)
        anchors = anchors + child_anchors
      }
    }
    @yaml.YSequence(elements, _) => {
      for i = 0; i < elements.length(); i = i + 1 {
        let new_path = path + [i.to_string()]
        let child_anchors = extract_yaml_anchors_with_path(elements[i], new_path)
        anchors = anchors + child_anchors
      }
    }
    @yaml.YAnchor(_, inner) => {
      let child_anchors = extract_yaml_anchors_with_path(inner, path)
      anchors = anchors + child_anchors
    }
    _ => ()
  }

  anchors
}

///|
/// Get the value kind string for a YAML node
fn yaml_value_kind(node : @yaml.YamlNode) -> String {
  match node {
    @yaml.YNull(_) => "null"
    @yaml.YBool(_, _) => "bool"
    @yaml.YNumber(_, _) => "number"
    @yaml.YString(_, _, _) => "string"
    @yaml.YSequence(_, _) => "array"
    @yaml.YMapping(_, _) => "object"
    @yaml.YAlias(_, _) => "alias"
    @yaml.YAnchor(_, _) => "anchor"
  }
}

///|
/// Extract string key from a YAML node (for anchor extraction)
fn extract_yaml_key(node : @yaml.YamlNode) -> String {
  match node {
    @yaml.YString(s, _, _) => s
    @yaml.YNumber(n, _) => n
    @yaml.YBool(true, _) => "true"
    @yaml.YBool(false, _) => "false"
    @yaml.YNull(_) => "null"
    _ => ""
  }
}

// Type aliases
type Span = @common.Span
