///|
/// Tracking printer for JSONC with position mapping

///|
/// A tracking printer that builds output string and records positions
pub struct TrackingPrinter {
  buf : StringBuilder
  mut line : Int
  mut column : Int
  mut offset : Int
  mut indent : Int
}

///|
/// Create a new tracking printer
pub fn TrackingPrinter::new() -> TrackingPrinter {
  { buf: StringBuilder::new(), line: 0, column: 0, offset: 0, indent: 0 }
}

///|
/// Get the current position
pub fn TrackingPrinter::current_pos(self : TrackingPrinter) -> @common.Pos {
  @common.Pos::new(self.line, self.column, self.offset)
}

///|
/// Get the output string so far
pub fn TrackingPrinter::to_string(self : TrackingPrinter) -> String {
  self.buf.to_string()
}

///|
/// Write a string and update position
pub fn TrackingPrinter::write(self : TrackingPrinter, s : String) -> Unit {
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    self.buf.write_char(ch)
    if ch == '\n' {
      self.line = self.line + 1
      self.column = 0
    } else {
      self.column = self.column + 1
    }
    self.offset = self.offset + 1
  }
}

///|
/// Write a newline
pub fn TrackingPrinter::newline(self : TrackingPrinter) -> Unit {
  self.write("\n")
}

///|
/// Write indentation
pub fn TrackingPrinter::write_indent(self : TrackingPrinter) -> Unit {
  for i = 0; i < self.indent; i = i + 1 {
    self.write(" ")
  }
}

///|
/// Set indent level
pub fn TrackingPrinter::set_indent(self : TrackingPrinter, level : Int) -> Unit {
  self.indent = level
}

///|
/// Print JSONC node with position tracking
pub fn print_jsonc_with_tracking(node : @jsonc.JsonNode) -> String {
  let printer = TrackingPrinter::new()
  printer.print_node(node)
  printer.to_string()
}

///|
/// Print a node
fn TrackingPrinter::print_node(self : TrackingPrinter, node : @jsonc.JsonNode) -> Unit {
  // Print leading trivia
  let trivia = node.trivia()
  self.print_trivia(trivia.leading, true)

  // Print content
  match node {
    @jsonc.JNull(_) => self.write("null")
    @jsonc.JBool(true, _) => self.write("true")
    @jsonc.JBool(false, _) => self.write("false")
    @jsonc.JNumber(n, _) => self.write(n)
    @jsonc.JString(s, _) => self.write(escape_json_string(s))
    @jsonc.JArray(elements, _) => self.print_array(elements)
    @jsonc.JObject(props, _) => self.print_object(props)
  }

  // Print trailing trivia
  self.print_trivia(trivia.trailing, false)
}

///|
/// Print trivia (comments)
fn TrackingPrinter::print_trivia(
  self : TrackingPrinter,
  comments : Array[@common.Comment],
  is_leading : Bool
) -> Unit {
  for comment in comments {
    let text = match comment.kind {
      @common.LineComment => "//" + comment.content
      @common.BlockComment => "/*" + comment.content + "*/"
    }
    if is_leading {
      self.write(text)
      self.newline()
    } else {
      self.write(" ")
      self.write(text)
    }
  }
}

///|
/// Print array
fn TrackingPrinter::print_array(self : TrackingPrinter, elements : Array[@jsonc.JsonNode]) -> Unit {
  self.write("[")
  if elements.is_empty() {
    self.write("]")
    return
  }

  self.set_indent(self.indent + 2)
  self.newline()

  for i = 0; i < elements.length(); i = i + 1 {
    self.write_indent()
    self.print_node(elements[i])
    if i < elements.length() - 1 {
      self.write(",")
    }
    self.newline()
  }

  self.set_indent(self.indent)
  self.write_indent()
  self.write("]")
}

///|
/// Print object
fn TrackingPrinter::print_object(self : TrackingPrinter, props : Array[@jsonc.JProperty]) -> Unit {
  self.write("{")
  if props.is_empty() {
    self.write("}")
    return
  }

  self.set_indent(self.indent + 2)
  self.newline()

  for i = 0; i < props.length(); i = i + 1 {
    let prop = props[i]
    self.write_indent()
    self.print_property(prop)
    if i < props.length() - 1 {
      self.write(",")
    }
    self.newline()
  }

  self.set_indent(self.indent)
  self.write_indent()
  self.write("}")
}

///|
/// Print property
fn TrackingPrinter::print_property(self : TrackingPrinter, prop : @jsonc.JProperty) -> Unit {
  // Print key trivia
  self.print_trivia(prop.key_trivia.leading, true)

  // Print key
  self.write(escape_json_string(prop.key))
  self.write(": ")

  // Print value
  self.print_node(prop.value)

  // Print key trailing trivia (after value, as it's a comment on the key-value pair)
  self.print_trivia(prop.key_trivia.trailing, false)
}

///|
/// Escape JSON string
fn escape_json_string(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ if ch.to_int() < 0x20 => {
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
/// Convert int to 4-digit hex
fn int_to_hex4(n : Int) -> String {
  let hex_chars = "0123456789abcdef"
  let buf = StringBuilder::new()
  buf.write_char(hex_chars[(n >> 12) & 0xf].to_int().unsafe_to_char())
  buf.write_char(hex_chars[(n >> 8) & 0xf].to_int().unsafe_to_char())
  buf.write_char(hex_chars[(n >> 4) & 0xf].to_int().unsafe_to_char())
  buf.write_char(hex_chars[n & 0xf].to_int().unsafe_to_char())
  buf.to_string()
}

// ============================================================================
// YAML Tracking Printer
// ============================================================================

///|
/// Print YAML node with position tracking
pub fn print_yaml_with_tracking(node : @yaml.YamlNode) -> String {
  let printer = TrackingPrinter::new()
  printer.print_yaml_node(node)
  printer.to_string()
}

///|
/// Print a YAML node
fn TrackingPrinter::print_yaml_node(self : TrackingPrinter, node : @yaml.YamlNode) -> Unit {
  // Print leading trivia
  let trivia = node.trivia()
  self.print_yaml_trivia(trivia.leading, true)

  // Print content
  match node {
    @yaml.YNull(_) => self.write("null")
    @yaml.YBool(true, _) => self.write("true")
    @yaml.YBool(false, _) => self.write("false")
    @yaml.YNumber(n, _) => self.write(n)
    @yaml.YString(s, style, _) => self.print_yaml_string(s, style)
    @yaml.YSequence(elements, _, _) => self.print_yaml_sequence(elements)
    @yaml.YMapping(pairs, _, _) => self.print_yaml_mapping(pairs)
    @yaml.YAlias(name, _) => self.write("*" + name)
    @yaml.YAnchor(name, inner) => {
      self.write("&" + name)
      self.write(" ")
      self.print_yaml_node(inner)
    }
  }

  // Print trailing trivia
  self.print_yaml_trivia(trivia.trailing, false)
}

///|
/// Print YAML string with appropriate quoting
fn TrackingPrinter::print_yaml_string(
  self : TrackingPrinter,
  s : String,
  style : @yaml.YamlScalarStyle
) -> Unit {
  match style {
    @yaml.Plain => {
      // Check if we need quotes
      if needs_yaml_quoting(s) {
        self.write("\"" + s + "\"")
      } else {
        self.write(s)
      }
    }
    @yaml.SingleQuoted => self.write("'" + s + "'")
    @yaml.DoubleQuoted => self.write("\"" + s + "\"")
    @yaml.Literal => self.print_yaml_literal_block(s)
    @yaml.Folded => self.print_yaml_folded_block(s)
  }
}

///|
/// Check if a string needs quoting in YAML
fn needs_yaml_quoting(s : String) -> Bool {
  if s.length() == 0 {
    return true
  }
  match s {
    "null" | "Null" | "NULL" | "~" => return true
    "true" | "True" | "TRUE" | "yes" | "Yes" | "YES" => return true
    "false" | "False" | "FALSE" | "no" | "No" | "NO" => return true
    _ => ()
  }
  // Check for special characters
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
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
      ch == '`' {
      return true
    }
  }
  let first = s[0].to_int().unsafe_to_char()
  if first == '-' || first == '?' || first == ' ' || first == '\t' {
    return true
  }
  false
}

///|
/// Print YAML literal block
fn TrackingPrinter::print_yaml_literal_block(self : TrackingPrinter, s : String) -> Unit {
  self.write("|")
  self.newline()
  let lines = split_lines_to_array(s)
  for line in lines {
    self.write_indent()
    self.write(line)
    self.newline()
  }
}

///|
/// Print YAML folded block
fn TrackingPrinter::print_yaml_folded_block(self : TrackingPrinter, s : String) -> Unit {
  self.write(">")
  self.newline()
  let lines = split_lines_to_array(s)
  for line in lines {
    self.write_indent()
    self.write(line)
    self.newline()
  }
}

///|
/// Print YAML sequence
fn TrackingPrinter::print_yaml_sequence(self : TrackingPrinter, elements : Array[@yaml.YamlNode]) -> Unit {
  if elements.is_empty() {
    self.write("[]")
    return
  }

  self.set_indent(self.indent + 2)
  for elem in elements {
    self.write("- ")
    let old_indent = self.indent
    self.indent = self.indent + 2
    self.print_yaml_node(elem)
    self.indent = old_indent
    self.newline()
  }
  self.set_indent(self.indent - 2)
}

///|
/// Print YAML mapping
fn TrackingPrinter::print_yaml_mapping(self : TrackingPrinter, pairs : Array[@yaml.YKeyValue]) -> Unit {
  if pairs.is_empty() {
    self.write("{}")
    return
  }

  self.set_indent(self.indent + 2)
  for pair in pairs {
    self.print_yaml_node(pair.key)
    self.write(":")
    // Print key trivia
    self.print_yaml_trivia(pair.key_trivia.leading, true)
    self.print_yaml_node(pair.value)
    self.print_yaml_trivia(pair.key_trivia.trailing, false)
    self.newline()
  }
  self.set_indent(self.indent - 2)
}

///|
/// Print YAML trivia (comments)
fn TrackingPrinter::print_yaml_trivia(
  self : TrackingPrinter,
  comments : Array[@common.Comment],
  is_leading : Bool
) -> Unit {
  for comment in comments {
    let text = "#" + comment.content
    if is_leading {
      self.write(text)
      self.newline()
    } else {
      self.write(" ")
      self.write(text)
    }
  }
}

///|
/// Split string into lines
fn split_lines_to_array(s : String) -> Array[String] {
  let lines : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
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
  if s.length() > 0 && s[s.length() - 1].to_int().unsafe_to_char() == '\n' {
    lines.push("")
  }
  lines
}
