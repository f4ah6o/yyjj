///|
/// YAML scalar style
pub enum YamlScalarStyle {
  Plain // unquoted
  SingleQuoted
  DoubleQuoted
  Literal // | block
  Folded // > block
} derive(Eq, Show)

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
} derive(Eq, Show)

///|
/// YAML key-value pair
pub struct YKeyValue {
  key : YamlNode
  key_trivia : @common.Trivia
  value : YamlNode
} derive(Eq, Show)

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
