///|
/// Convert YAML CST to pretty-printable document
pub fn to_doc(node : YamlNode) -> @pretty.Doc {
  node_to_doc(node, 0)
}

///|
fn node_to_doc(node : YamlNode, indent : Int) -> @pretty.Doc {
  let trivia = node.trivia()
  let leading = trivia_to_doc(trivia.leading)
  let trailing = trivia_to_doc(trivia.trailing)
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
    Plain => @pretty.text(s)
    SingleQuoted => @pretty.text("'" + escape_single_quoted(s) + "'")
    DoubleQuoted => @pretty.text("\"" + escape_double_quoted(s) + "\"")
    Literal => literal_block_to_doc(s)
    Folded => folded_block_to_doc(s)
  }
}

///|
fn escape_single_quoted(s : String) -> String {
  // In single-quoted YAML, only '' is an escape
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = Char::from_int(s[i].to_int())
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
    let ch = Char::from_int(s[i].to_int())
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
    let elem_doc = node_to_doc(elem, indent + 2)
    docs.push(@pretty.concat([@pretty.text("- "), elem_doc]))
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
    let key_doc = node_to_doc(pair.key, indent)
    let value_doc = node_to_doc(pair.value, indent + 2)
    // Check if value is a nested structure
    let is_nested = match pair.value {
      YSequence(_, _) | YMapping(_, _) => true
      _ => false
    }
    if is_nested {
      docs.push(
        @pretty.concat([key_doc, @pretty.text(":"), @pretty.hardline(), @pretty.nest(2, value_doc)]),
      )
    } else {
      docs.push(@pretty.concat([key_doc, @pretty.text(": "), value_doc]))
    }
  }
  @pretty.join(docs, @pretty.hardline())
}

///|
fn trivia_to_doc(comments : Array[@common.Comment]) -> @pretty.Doc {
  if comments.is_empty() {
    return @pretty.Doc::nil()
  }
  let docs : Array[@pretty.Doc] = []
  for i = 0; i < comments.length(); i = i + 1 {
    let comment = comments[i]
    docs.push(@pretty.text(" #" + comment.content))
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
