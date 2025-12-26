///|
/// Transform JSONC CST to YAML CST, preserving comments
pub fn jsonc_to_yaml(node : @jsonc.JsonNode) -> @yaml.YamlNode {
  transform_node(node)
}

///|
fn transform_node(node : @jsonc.JsonNode) -> @yaml.YamlNode {
  let trivia = transform_trivia(node.trivia())
  match node {
    @jsonc.JNull(_) => @yaml.YamlNode::null_with_trivia(trivia)
    @jsonc.JBool(v, _) => @yaml.YamlNode::bool_with_trivia(v, trivia)
    @jsonc.JNumber(n, _) => @yaml.YamlNode::number_with_trivia(n, trivia)
    @jsonc.JString(s, _) => transform_string(s, trivia)
    @jsonc.JArray(elements, _) => {
      let yaml_elements = elements.map(fn(e) { transform_node(e) })
      @yaml.YamlNode::sequence_with_trivia(yaml_elements, trivia)
    }
    @jsonc.JObject(props, _) => {
      let pairs = props.map(
        fn(p) {
          let key = @yaml.YamlNode::string_with_trivia(p.key, @yaml.YamlScalarStyle::plain(), @common.Trivia::empty())
          let key_trivia = transform_trivia(p.key_trivia)
          let value = transform_node(p.value)
          @yaml.YKeyValue::new(key, key_trivia, value)
        },
      )
      @yaml.YamlNode::mapping_with_trivia(pairs, trivia)
    }
  }
}

///|
fn transform_string(s : String, trivia : @common.Trivia) -> @yaml.YamlNode {
  // Determine if the string needs quoting
  let style = if needs_quoting(s) {
    @yaml.YamlScalarStyle::double_quoted()
  } else {
    @yaml.YamlScalarStyle::plain()
  }
  @yaml.YamlNode::string_with_trivia(s, style, trivia)
}

///|
fn needs_quoting(s : String) -> Bool {
  if s.length() == 0 {
    return true
  }
  // Check for YAML special values
  match s {
    "null" | "Null" | "NULL" | "~" => return true
    "true" | "True" | "TRUE" | "yes" | "Yes" | "YES" | "on" | "On" | "ON" =>
      return true
    "false" | "False" | "FALSE" | "no" | "No" | "NO" | "off" | "Off" | "OFF" =>
      return true
    _ => ()
  }
  // Check for special characters
  for i = 0; i < s.length(); i = i + 1 {
    let ch = Char::from_int(s[i].to_int())
    if ch == ':' ||
      ch == '#' ||
      ch == '[' ||
      ch == ']' ||
      ch == '{' ||
      ch == '}' ||
      ch == ',' ||
      ch == '&' ||
      ch == '*' ||
      ch == '!' ||
      ch == '|' ||
      ch == '>' ||
      ch == '\'' ||
      ch == '"' ||
      ch == '%' ||
      ch == '@' ||
      ch == '`' ||
      ch == '\n' ||
      ch == '\r' {
      return true
    }
  }
  // Check if starts with special character
  let first = Char::from_int(s[0].to_int())
  if first == '-' || first == '?' || first == ' ' || first == '\t' {
    return true
  }
  false
}

///|
fn transform_trivia(trivia : @common.Trivia) -> @common.Trivia {
  // Transform block comments to line comments
  let leading = trivia.leading.map(fn(c) { transform_comment(c) }).flatten()
  let trailing = trivia.trailing.map(fn(c) { transform_comment(c) }).flatten()
  @common.Trivia::new(leading, trailing)
}

///|
fn transform_comment(comment : @common.Comment) -> Array[@common.Comment] {
  match comment.kind {
    @common.LineComment => [comment]
    @common.BlockComment => {
      // Split block comment into multiple line comments
      let lines = split_lines(comment.content)
      lines.mapi(
        fn(i, line) {
          @common.Comment::new(
            line,
            @common.CommentKind::line(),
            comment.span,
            i > 0,
          )
        },
      )
    }
  }
}

///|
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = Char::from_int(s[i].to_int())
    if ch == '\n' {
      lines.push(buf.to_string())
      buf.reset()
    } else if ch != '\r' {
      buf.write_char(ch)
    }
  }
  let last = buf.to_string()
  if last.length() > 0 {
    lines.push(last)
  }
  lines
}
