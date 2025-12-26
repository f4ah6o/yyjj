///|
/// Document algebra for pretty printing (Wadler-Lindig style)
pub enum Doc {
  Nil // Empty document
  Text(String) // Literal text
  Line // Newline or space (group-dependent)
  HardLine // Always newline
  Concat(Doc, Doc) // Sequential composition
  Nest(Int, Doc) // Increase indent
  Group(Doc) // Try flat first, then break
  FlatAlt(Doc, Doc) // Alternative for flat vs broken
} derive(Eq, Show)

///|
/// Empty document
pub fn Doc::nil() -> Doc {
  Nil
}

///|
/// Literal text
pub fn Doc::text(s : String) -> Doc {
  Text(s)
}

///|
/// Soft line break (space when flat, newline when broken)
pub fn Doc::line() -> Doc {
  Line
}

///|
/// Hard line break (always newline)
pub fn Doc::hardline() -> Doc {
  HardLine
}

///|
/// Nest document by indent
pub fn Doc::nest(indent : Int, doc : Doc) -> Doc {
  Nest(indent, doc)
}

///|
/// Group for layout decision
pub fn Doc::group(doc : Doc) -> Doc {
  Group(doc)
}

///|
/// Concatenate two documents
pub fn Doc::concat(self : Doc, other : Doc) -> Doc {
  Concat(self, other)
}

///|
/// Concatenate with a separator
pub fn Doc::concat_with(docs : Array[Doc], sep : Doc) -> Doc {
  if docs.is_empty() {
    return Nil
  }
  let mut result = docs[0]
  for i = 1; i < docs.length(); i = i + 1 {
    result = Concat(result, Concat(sep, docs[i]))
  }
  result
}
