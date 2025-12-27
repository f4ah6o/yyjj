///|
/// Convert YAML CST to pretty-printable document
pub fn to_doc(node : YamlNode) -> @pretty.Doc {
  node_to_doc(node, 0)
}

///|
fn node_to_doc(node : YamlNode, indent : Int) -> @pretty.Doc {
  let trivia = node.trivia()
  let leading = trivia_to_doc(trivia.leading, true)
  let trailing = trivia_to_doc(trivia.trailing, false)
  let content = match node {
    YNull(_) => @pretty.text("null")
    YBool(true, _) => @pretty.text("true")
    YBool(false, _) => @pretty.text("false")
    YNumber(n, _) => @pretty.text(n)
    YString(s, style, _) => string_to_doc(s, style)
    YSequence(elements, _) => sequence_to_doc(elements, indent)
    YMapping(pairs, _) => mapping_to_doc(pairs, indent)
    YAlias(name, _) => @pretty.text("*" + name)
    YAnchor(name, value) =>
      @pretty.concat([@pretty.text("&" + name + " "), node_to_doc(value, indent)])
  }
  @pretty.concat([leading, content, trailing])
}

///|
fn string_to_doc(s : String, style : YamlScalarStyle) -> @pretty.Doc {
  match style {
    Plain =>
      // Quote strings that look like numbers, bools, or null to preserve type
      if needs_quoting(s) {
        @pretty.text("\"" + escape_double_quoted(s) + "\"")
      } else {
        @pretty.text(s)
      }
    SingleQuoted => @pretty.text("'" + escape_single_quoted(s) + "'")
    DoubleQuoted => @pretty.text("\"" + escape_double_quoted(s) + "\"")
    Literal => literal_block_to_doc(s)
    Folded => folded_block_to_doc(s)
  }
}

///|
/// Check if a string needs quoting in YAML to preserve its type
fn needs_quoting(s : String) -> Bool {
  if s.is_empty() {
    return true
  }
  // Check for YAML keywords
  match s {
    "null" | "Null" | "NULL" | "~" => true
    "true" | "True" | "TRUE" | "yes" | "Yes" | "YES" | "on" | "On" | "ON" =>
      true
    "false" | "False" | "FALSE" | "no" | "No" | "NO" | "off" | "Off" | "OFF" =>
      true
    _ => looks_like_number(s)
  }
}

///|
/// Check if string looks like a number (would be parsed as number in YAML)
fn looks_like_number(s : String) -> Bool {
  if s.is_empty() {
    return false
  }
  let mut i = 0
  // Optional minus
  if s[0].to_int().unsafe_to_char() == '-' {
    i += 1
    if i >= s.length() {
      return false
    }
  }
  // Check digits
  let first_digit = s[i].to_int().unsafe_to_char()
  if first_digit < '0' || first_digit > '9' {
    return false
  }
  // Rest must be digits, dots, or exponent chars
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if (ch >= '0' && ch <= '9') || ch == '.' || ch == 'e' || ch == 'E' ||
       ch == '+' || ch == '-' {
      i += 1
    } else {
      return false
    }
  }
  true
}

///|
fn escape_single_quoted(s : String) -> String {
  // In single-quoted YAML, only '' is an escape
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\'' {
      buf.write_string("''")
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
fn escape_double_quoted(s : String) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
fn literal_block_to_doc(s : String) -> @pretty.Doc {
  @pretty.concat([@pretty.text("|"), @pretty.hardline(), @pretty.text(s)])
}

///|
fn folded_block_to_doc(s : String) -> @pretty.Doc {
  @pretty.concat([@pretty.text(">"), @pretty.hardline(), @pretty.text(s)])
}

///|
fn sequence_to_doc(elements : Array[YamlNode], indent : Int) -> @pretty.Doc {
  if elements.is_empty() {
    return @pretty.text("[]")
  }
  let docs : Array[@pretty.Doc] = []
  for i = 0; i < elements.length(); i = i + 1 {
    let elem = elements[i]
    // When element is a mapping, the first key goes after "- " but subsequent
    // keys need to be indented. We handle this by splitting the mapping.
    match elem {
      YMapping(pairs, trivia) if pairs.length() > 1 => {
        // First pair: "- key: value"
        let first_pair = pairs[0]
        let first_key_leading = trivia_to_doc(first_pair.key_trivia.leading, true)
        let first_key_doc = node_to_doc(first_pair.key, indent + 2)
        let first_value_doc = node_to_doc(first_pair.value, indent + 4)
        let first_key_trailing = trivia_to_doc(first_pair.key_trivia.trailing, false)
        let is_first_nested = match first_pair.value {
          YSequence(_, _) | YMapping(_, _) => true
          _ => false
        }
        let first_doc = if is_first_nested {
          @pretty.concat([first_key_leading, first_key_doc, @pretty.text(":"), first_key_trailing, @pretty.nest(2, @pretty.concat([@pretty.hardline(), first_value_doc]))])
        } else {
          @pretty.concat([first_key_leading, first_key_doc, @pretty.text(":"), first_key_trailing, @pretty.text(" "), first_value_doc])
        }

        // Remaining pairs need to be indented by 2 (to align with first key)
        let rest_docs : Array[@pretty.Doc] = []
        for j = 1; j < pairs.length(); j = j + 1 {
          let pair = pairs[j]
          let key_leading = trivia_to_doc(pair.key_trivia.leading, true)
          let key_doc = node_to_doc(pair.key, indent + 2)
          let value_doc = node_to_doc(pair.value, indent + 4)
          let key_trailing = trivia_to_doc(pair.key_trivia.trailing, false)
          let is_nested = match pair.value {
            YSequence(_, _) | YMapping(_, _) => true
            _ => false
          }
          if is_nested {
            rest_docs.push(
              @pretty.concat([key_leading, key_doc, @pretty.text(":"), key_trailing, @pretty.nest(2, @pretty.concat([@pretty.hardline(), value_doc]))]),
            )
          } else {
            rest_docs.push(@pretty.concat([key_leading, key_doc, @pretty.text(":"), key_trailing, @pretty.text(" "), value_doc]))
          }
        }
        let leading_trivia = trivia_to_doc(trivia.leading, true)
        let rest_joined = @pretty.join(rest_docs, @pretty.hardline())
        docs.push(@pretty.concat([leading_trivia, @pretty.text("- "), first_doc, @pretty.nest(2, @pretty.concat([@pretty.hardline(), rest_joined]))]))
      }
      _ => {
        let elem_doc = node_to_doc(elem, indent + 2)
        docs.push(@pretty.concat([@pretty.text("- "), elem_doc]))
      }
    }
  }
  @pretty.join(docs, @pretty.hardline())
}

///|
fn mapping_to_doc(pairs : Array[YKeyValue], indent : Int) -> @pretty.Doc {
  if pairs.is_empty() {
    return @pretty.text("{}")
  }
  let docs : Array[@pretty.Doc] = []
  for i = 0; i < pairs.length(); i = i + 1 {
    let pair = pairs[i]
    // Output key_trivia leading comments
    let key_leading = trivia_to_doc(pair.key_trivia.leading, true)
    let key_doc = node_to_doc(pair.key, indent)
    let value_doc = node_to_doc(pair.value, indent + 2)
    // Output key_trivia trailing comments
    let key_trailing = trivia_to_doc(pair.key_trivia.trailing, false)
    // Check if value is a nested structure
    let is_nested = match pair.value {
      YSequence(_, _) | YMapping(_, _) => true
      _ => false
    }
    if is_nested {
      // nest must wrap hardline for indentation to apply
      docs.push(
        @pretty.concat([key_leading, key_doc, @pretty.text(":"), key_trailing, @pretty.nest(2, @pretty.concat([@pretty.hardline(), value_doc]))]),
      )
    } else {
      docs.push(@pretty.concat([key_leading, key_doc, @pretty.text(":"), key_trailing, @pretty.text(" "), value_doc]))
    }
  }
  @pretty.join(docs, @pretty.hardline())
}

///|
fn trivia_to_doc(comments : Array[@common.Comment], is_leading : Bool) -> @pretty.Doc {
  if comments.is_empty() {
    return @pretty.Doc::nil()
  }
  let docs : Array[@pretty.Doc] = []
  for i = 0; i < comments.length(); i = i + 1 {
    let comment = comments[i]
    let text = "#" + comment.content
    if is_leading {
      docs.push(@pretty.concat([@pretty.text(text), @pretty.hardline()]))
    } else {
      docs.push(@pretty.concat([@pretty.text(" "), @pretty.text(text)]))
    }
  }
  @pretty.concat(docs)
}

///|
/// Print YAML to string
pub fn print(node : YamlNode, width? : Int) -> String {
  let w = width.unwrap_or(80)
  let doc = to_doc(node)
  @pretty.render(doc, w)
}
