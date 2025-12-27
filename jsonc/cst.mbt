///|
/// JSONC CST node types
pub enum JsonNode {
  JNull(@common.Trivia)
  JBool(Bool, @common.Trivia)
  JNumber(String, @common.Trivia) // String to preserve precision
  JString(String, @common.Trivia)
  JArray(Array[JsonNode], @common.Trivia)
  JObject(Array[JProperty], @common.Trivia)
} derive(Eq, Show, Arbitrary)

///|
/// Object property with key and value
pub struct JProperty {
  key : String
  key_trivia : @common.Trivia // Trivia attached to the key
  value : JsonNode
} derive(Eq, Show, Arbitrary)

///|
/// Create a new property
pub fn JProperty::new(
  key : String,
  key_trivia : @common.Trivia,
  value : JsonNode
) -> JProperty {
  { key, key_trivia, value }
}

///|
/// Get trivia from any JsonNode
pub fn JsonNode::trivia(self : JsonNode) -> @common.Trivia {
  match self {
    JNull(t) => t
    JBool(_, t) => t
    JNumber(_, t) => t
    JString(_, t) => t
    JArray(_, t) => t
    JObject(_, t) => t
  }
}

///|
/// Create a node with new trivia
pub fn JsonNode::with_trivia(self : JsonNode, trivia : @common.Trivia) -> JsonNode {
  match self {
    JNull(_) => JNull(trivia)
    JBool(v, _) => JBool(v, trivia)
    JNumber(v, _) => JNumber(v, trivia)
    JString(v, _) => JString(v, trivia)
    JArray(v, _) => JArray(v, trivia)
    JObject(v, _) => JObject(v, trivia)
  }
}

///|
/// Create a null node
pub fn JsonNode::null() -> JsonNode {
  JNull(@common.Trivia::empty())
}

///|
/// Create a boolean node
pub fn JsonNode::bool(value : Bool) -> JsonNode {
  JBool(value, @common.Trivia::empty())
}

///|
/// Create a number node
pub fn JsonNode::number(value : String) -> JsonNode {
  JNumber(value, @common.Trivia::empty())
}

///|
/// Create a string node
pub fn JsonNode::string(value : String) -> JsonNode {
  JString(value, @common.Trivia::empty())
}

///|
/// Create an array node
pub fn JsonNode::array(elements : Array[JsonNode]) -> JsonNode {
  JArray(elements, @common.Trivia::empty())
}

///|
/// Create an object node
pub fn JsonNode::object(properties : Array[JProperty]) -> JsonNode {
  JObject(properties, @common.Trivia::empty())
}

///|
/// Create a null node with trivia
pub fn JsonNode::null_with_trivia(trivia : @common.Trivia) -> JsonNode {
  JNull(trivia)
}

///|
/// Create a boolean node with trivia
pub fn JsonNode::bool_with_trivia(value : Bool, trivia : @common.Trivia) -> JsonNode {
  JBool(value, trivia)
}

///|
/// Create a number node with trivia
pub fn JsonNode::number_with_trivia(value : String, trivia : @common.Trivia) -> JsonNode {
  JNumber(value, trivia)
}

///|
/// Create a string node with trivia
pub fn JsonNode::string_with_trivia(value : String, trivia : @common.Trivia) -> JsonNode {
  JString(value, trivia)
}

///|
/// Create an array node with trivia
pub fn JsonNode::array_with_trivia(elements : Array[JsonNode], trivia : @common.Trivia) -> JsonNode {
  JArray(elements, trivia)
}

///|
/// Create an object node with trivia
pub fn JsonNode::object_with_trivia(properties : Array[JProperty], trivia : @common.Trivia) -> JsonNode {
  JObject(properties, trivia)
}
