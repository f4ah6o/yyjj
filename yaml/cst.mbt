///|
/// YAML scalar style
pub enum YamlScalarStyle {
  Plain // unquoted
  SingleQuoted
  DoubleQuoted
  Literal // | block
  Folded // > block
} derive(Eq, Show, Arbitrary)

///| Factory function for Plain style
pub fn YamlScalarStyle::plain() -> YamlScalarStyle {
  Plain
}

///| Factory function for SingleQuoted style
pub fn YamlScalarStyle::single_quoted() -> YamlScalarStyle {
  SingleQuoted
}

///| Factory function for DoubleQuoted style
pub fn YamlScalarStyle::double_quoted() -> YamlScalarStyle {
  DoubleQuoted
}

///| Factory function for Literal style
pub fn YamlScalarStyle::literal() -> YamlScalarStyle {
  Literal
}

///| Factory function for Folded style
pub fn YamlScalarStyle::folded() -> YamlScalarStyle {
  Folded
}

///|
/// YAML CST node types
pub enum YamlNode {
  YNull(@common.Trivia)
  YBool(Bool, @common.Trivia)
  YNumber(String, @common.Trivia)
  YString(String, YamlScalarStyle, @common.Trivia)
  YSequence(Array[YamlNode], @common.Trivia)
  YMapping(Array[YKeyValue], @common.Trivia)
  YAlias(String, @common.Trivia) // *alias reference
  YAnchor(String, YamlNode) // &anchor definition
} derive(Eq, Show, Arbitrary)

///|
/// YAML key-value pair
pub struct YKeyValue {
  key : YamlNode
  key_trivia : @common.Trivia
  value : YamlNode
} derive(Eq, Show, Arbitrary)

///|
/// Create a new key-value pair
pub fn YKeyValue::new(
  key : YamlNode,
  key_trivia : @common.Trivia,
  value : YamlNode
) -> YKeyValue {
  { key, key_trivia, value }
}

///|
/// Get trivia from any YamlNode
pub fn YamlNode::trivia(self : YamlNode) -> @common.Trivia {
  match self {
    YNull(t) => t
    YBool(_, t) => t
    YNumber(_, t) => t
    YString(_, _, t) => t
    YSequence(_, t) => t
    YMapping(_, t) => t
    YAlias(_, t) => t
    YAnchor(_, node) => node.trivia()
  }
}

///|
/// Create a null node
pub fn YamlNode::null() -> YamlNode {
  YNull(@common.Trivia::empty())
}

///|
/// Create a boolean node
pub fn YamlNode::bool(value : Bool) -> YamlNode {
  YBool(value, @common.Trivia::empty())
}

///|
/// Create a number node
pub fn YamlNode::number(value : String) -> YamlNode {
  YNumber(value, @common.Trivia::empty())
}

///|
/// Create a string node
pub fn YamlNode::string(value : String, style : YamlScalarStyle) -> YamlNode {
  YString(value, style, @common.Trivia::empty())
}

///|
/// Create a sequence node
pub fn YamlNode::sequence(elements : Array[YamlNode]) -> YamlNode {
  YSequence(elements, @common.Trivia::empty())
}

///|
/// Create a mapping node
pub fn YamlNode::mapping(pairs : Array[YKeyValue]) -> YamlNode {
  YMapping(pairs, @common.Trivia::empty())
}

///|
/// Create a null node with trivia
pub fn YamlNode::null_with_trivia(trivia : @common.Trivia) -> YamlNode {
  YNull(trivia)
}

///|
/// Create a boolean node with trivia
pub fn YamlNode::bool_with_trivia(value : Bool, trivia : @common.Trivia) -> YamlNode {
  YBool(value, trivia)
}

///|
/// Create a number node with trivia
pub fn YamlNode::number_with_trivia(value : String, trivia : @common.Trivia) -> YamlNode {
  YNumber(value, trivia)
}

///|
/// Create a string node with trivia
pub fn YamlNode::string_with_trivia(value : String, style : YamlScalarStyle, trivia : @common.Trivia) -> YamlNode {
  YString(value, style, trivia)
}

///|
/// Create a sequence node with trivia
pub fn YamlNode::sequence_with_trivia(elements : Array[YamlNode], trivia : @common.Trivia) -> YamlNode {
  YSequence(elements, trivia)
}

///|
/// Create a mapping node with trivia
pub fn YamlNode::mapping_with_trivia(pairs : Array[YKeyValue], trivia : @common.Trivia) -> YamlNode {
  YMapping(pairs, trivia)
}
