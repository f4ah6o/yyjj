///|
/// Convert JSONC CST to pretty-printable document
pub fn to_doc(node : JsonNode) -> @pretty.Doc {
  to_doc_with_trivia(node)
}

///|
fn to_doc_with_trivia(node : JsonNode) -> @pretty.Doc {
  let trivia = node.trivia()
  let leading = trivia_to_doc(trivia.leading, true)
  let trailing = trivia_to_doc(trivia.trailing, false)
  let content = node_to_doc(node)
  @pretty.concat([leading, content, trailing])
}

///|
fn node_to_doc(node : JsonNode) -> @pretty.Doc {
  match node {
    JNull(_) => @pretty.text("null")
    JBool(true, _) => @pretty.text("true")
    JBool(false, _) => @pretty.text("false")
    JNumber(n, _) => @pretty.text(n)
    JString(s, _) => @pretty.text(escape_json_string(s))
    JArray(elements, _) => array_to_doc(elements)
    JObject(props, _) => object_to_doc(props)
  }
}

///|
fn array_to_doc(elements : Array[JsonNode]) -> @pretty.Doc {
  if elements.is_empty() {
    return @pretty.text("[]")
  }
  let open = @pretty.text("[")
  let close = @pretty.text("]")
  let content_docs : Array[@pretty.Doc] = []
  for i = 0; i < elements.length(); i = i + 1 {
    let elem_doc = to_doc_with_trivia(elements[i])
    if i < elements.length() - 1 {
      content_docs.push(@pretty.concat([elem_doc, @pretty.text(",")]))
    } else {
      content_docs.push(elem_doc)
    }
  }
  let content = @pretty.join(content_docs, @pretty.line())
  @pretty.group(
    @pretty.concat([open, @pretty.nest(2, @pretty.concat([@pretty.line(), content])), @pretty.line(), close]),
  )
}

///|
fn object_to_doc(props : Array[JProperty]) -> @pretty.Doc {
  if props.is_empty() {
    return @pretty.text("{}")
  }
  let open = @pretty.text("{")
  let close = @pretty.text("}")
  let prop_docs : Array[@pretty.Doc] = []
  for i = 0; i < props.length(); i = i + 1 {
    let prop = props[i]
    let key_leading = trivia_to_doc(prop.key_trivia.leading, true)
    let key_doc = @pretty.text(escape_json_string(prop.key))
    let key_trailing = trivia_to_doc(prop.key_trivia.trailing, false)
    let value_doc = to_doc_with_trivia(prop.value)
    let prop_doc = @pretty.concat([key_leading, key_doc, key_trailing, @pretty.text(": "), value_doc])
    if i < props.length() - 1 {
      prop_docs.push(@pretty.concat([prop_doc, @pretty.text(",")]))
    } else {
      prop_docs.push(prop_doc)
    }
  }
  let content = @pretty.join(prop_docs, @pretty.line())
  @pretty.group(
    @pretty.concat([open, @pretty.nest(2, @pretty.concat([@pretty.line(), content])), @pretty.line(), close]),
  )
}

///|
fn trivia_to_doc(
  comments : Array[@common.Comment],
  is_leading : Bool
) -> @pretty.Doc {
  if comments.is_empty() {
    return @pretty.Doc::nil()
  }
  let docs : Array[@pretty.Doc] = []
  for i = 0; i < comments.length(); i = i + 1 {
    let comment = comments[i]
    let text = match comment.kind {
      @common.LineComment => "//" + comment.content
      @common.BlockComment => "/*" + comment.content + "*/"
    }
    if is_leading {
      docs.push(@pretty.concat([@pretty.text(text), @pretty.hardline()]))
    } else {
      docs.push(@pretty.concat([@pretty.text(" "), @pretty.text(text)]))
    }
  }
  @pretty.concat(docs)
}

///|
fn escape_json_string(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  for i = 0; i < s.length(); i = i + 1 {
    let ch = Char::from_int(s[i].to_int())
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ if ch.to_int() < 0x20 => {
        // Control character - use unicode escape
        let hex = int_to_hex4(ch.to_int())
        buf.write_string("\\u")
        buf.write_string(hex)
      }
      _ => buf.write_char(ch)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn int_to_hex4(n : Int) -> String {
  let hex_chars = "0123456789abcdef"
  let buf = StringBuilder::new()
  buf.write_char(Char::from_int(hex_chars[(n >> 12) & 0xf].to_int()))
  buf.write_char(Char::from_int(hex_chars[(n >> 8) & 0xf].to_int()))
  buf.write_char(Char::from_int(hex_chars[(n >> 4) & 0xf].to_int()))
  buf.write_char(Char::from_int(hex_chars[n & 0xf].to_int()))
  buf.to_string()
}

///|
/// Print JSONC to string
pub fn print(node : JsonNode, width? : Int) -> String {
  let w = width.or(80)
  let doc = to_doc(node)
  @pretty.render(doc, w)
}
