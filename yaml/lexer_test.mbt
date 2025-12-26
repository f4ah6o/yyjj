///|
test "yaml_lex_simple_mapping" {
  let lexer = @yaml.Lexer::new("key: value")
  let tokens = lexer.tokenize()
  let kinds = tokens
    .filter(fn(t) { not(t.is_trivia()) })
    .map(fn(t) { t.kind })
  inspect(kinds, content="[PlainScalar(\"key\"), Colon, PlainScalar(\"value\"), Eof]")
}

///|
test "yaml_lex_sequence" {
  let source = (
    #|- item1
    #|- item2
  )
  let lexer = @yaml.Lexer::new(source)
  let tokens = lexer.tokenize()
  let dashes = tokens.filter(
    fn(t) {
      match t.kind {
        @yaml.Dash => true
        _ => false
      }
    },
  )
  inspect(dashes.length(), content="2")
}

///|
test "yaml_lex_comment" {
  let lexer = @yaml.Lexer::new("key: value # comment")
  let tokens = lexer.tokenize()
  let comments = tokens.filter(fn(t) { t.is_comment() })
  inspect(comments.length(), content="1")
}

///|
test "yaml_lex_quoted_string" {
  let lexer = @yaml.Lexer::new("'single quoted'")
  let tokens = lexer.tokenize()
  guard tokens[0].kind is @yaml.SingleQuotedScalar(s) else { return }
  inspect(s, content="single quoted")
}

///|
test "yaml_lex_double_quoted" {
  let lexer = @yaml.Lexer::new("\"double\\nquoted\"")
  let tokens = lexer.tokenize()
  guard tokens[0].kind is @yaml.DoubleQuotedScalar(s) else { return }
  inspect(s, content="double\nquoted")
}

///|
test "yaml_lex_anchor_alias" {
  let source = (
    #|&anchor value
    #|*anchor
  )
  let lexer = @yaml.Lexer::new(source)
  let tokens = lexer.tokenize()
  let anchors = tokens.filter(
    fn(t) {
      match t.kind {
        @yaml.Anchor(_) => true
        _ => false
      }
    },
  )
  let aliases = tokens.filter(
    fn(t) {
      match t.kind {
        @yaml.Alias(_) => true
        _ => false
      }
    },
  )
  inspect(anchors.length(), content="1")
  inspect(aliases.length(), content="1")
}

///|
test "yaml_lex_keywords" {
  let lexer1 = @yaml.Lexer::new("true")
  let tokens1 = lexer1.tokenize()
  guard tokens1[0].kind is @yaml.TrueValue else { return }
  let lexer2 = @yaml.Lexer::new("false")
  let tokens2 = lexer2.tokenize()
  guard tokens2[0].kind is @yaml.FalseValue else { return }
  let lexer3 = @yaml.Lexer::new("null")
  let tokens3 = lexer3.tokenize()
  guard tokens3[0].kind is @yaml.NullValue else { return }
}
