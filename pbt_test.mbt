///|
/// Property-based tests for JSONC/YAML parsing and transformation

///|
/// Strip trivia from JsonNode for structural comparison
fn strip_jsonc_trivia(node : @jsonc.JsonNode) -> @jsonc.JsonNode {
  let empty = @common.Trivia::empty()
  match node {
    @jsonc.JNull(_) => @jsonc.JsonNode::null_with_trivia(empty)
    @jsonc.JBool(v, _) => @jsonc.JsonNode::bool_with_trivia(v, empty)
    @jsonc.JNumber(v, _) => @jsonc.JsonNode::number_with_trivia(v, empty)
    @jsonc.JString(v, _) => @jsonc.JsonNode::string_with_trivia(v, empty)
    @jsonc.JArray(elements, _) => {
      let stripped = elements.map(strip_jsonc_trivia)
      @jsonc.JsonNode::array_with_trivia(stripped, empty)
    }
    @jsonc.JObject(props, _) => {
      let stripped = props.map(fn(p) {
        @jsonc.JProperty::new(p.key, empty, strip_jsonc_trivia(p.value))
      })
      @jsonc.JsonNode::object_with_trivia(stripped, empty)
    }
  }
}

///|
/// Strip trivia from YamlNode for structural comparison
fn strip_yaml_trivia(node : @yaml.YamlNode) -> @yaml.YamlNode {
  let empty = @common.Trivia::empty()
  match node {
    @yaml.YNull(_) => @yaml.YamlNode::null_with_trivia(empty)
    @yaml.YBool(v, _) => @yaml.YamlNode::bool_with_trivia(v, empty)
    @yaml.YNumber(v, _) => @yaml.YamlNode::number_with_trivia(v, empty)
    @yaml.YString(v, style, _) => @yaml.YamlNode::string_with_trivia(v, style, empty)
    @yaml.YSequence(elements, style, _) => {
      let stripped = elements.map(strip_yaml_trivia)
      @yaml.YamlNode::sequence_with_style(stripped, style, empty)
    }
    @yaml.YMapping(pairs, style, _) => {
      let stripped = pairs.map(fn(kv) {
        @yaml.YKeyValue::new(
          strip_yaml_trivia(kv.key),
          empty,
          strip_yaml_trivia(kv.value),
        )
      })
      @yaml.YamlNode::mapping_with_style(stripped, style, empty)
    }
    @yaml.YAlias(name, _) => @yaml.YamlNode::alias_with_trivia(name, empty)
    @yaml.YAnchor(name, inner) => @yaml.YamlNode::anchor(name, strip_yaml_trivia(inner))
  }
}

///|
/// Generate a valid JSON number string
fn gen_valid_number() -> @qc.Gen[String] {
  @qc.one_of(
    [
      @qc.pure("0"),
      @qc.pure("1"),
      @qc.pure("42"),
      @qc.pure("-1"),
      @qc.pure("3.14"),
      @qc.pure("-0.5"),
      @qc.pure("1e10"),
      @qc.pure("1.5e-3"),
      {
        let gen : @qc.Gen[Int] = @qc.Gen::spawn()
        gen.fmap(fn(n) { n.to_string() })
      },
    ],
  )
}

///|
/// Generate a safe string (no control chars that would break parsing)
fn gen_safe_string() -> @qc.Gen[String] {
  let gen : @qc.Gen[String] = @qc.Gen::spawn()
  gen.fmap(fn(s) {
    let buf = StringBuilder::new()
    for c in s {
      // Filter out control characters and problematic chars
      if c.to_int() >= 0x20 && c.to_int() < 0x7f {
        buf.write_char(c)
      }
    }
    buf.to_string()
  })
}

///|
/// Generate a non-empty safe string for use as object keys
/// Empty keys and keys with special chars cause issues in YAML roundtrip
fn gen_safe_key() -> @qc.Gen[String] {
  let gen : @qc.Gen[String] = @qc.Gen::spawn()
  gen.fmap(fn(s) {
    let buf = StringBuilder::new()
    for c in s {
      // Only allow alphanumeric and underscore for safe keys
      let code = c.to_int()
      if (code >= 0x30 && code <= 0x39) ||
         (code >= 0x41 && code <= 0x5a) ||
         (code >= 0x61 && code <= 0x7a) ||
         code == 0x5f {
        buf.write_char(c)
      }
    }
    let result = buf.to_string()
    if result.is_empty() {
      "key" // Default non-empty key
    } else {
      result
    }
  })
}

///|
/// Generate a simple scalar JsonNode (no recursion)
fn gen_json_scalar() -> @qc.Gen[@jsonc.JsonNode] {
  let empty = @common.Trivia::empty()
  @qc.one_of(
    [
      @qc.pure(@jsonc.JsonNode::null_with_trivia(empty)),
      { let g : @qc.Gen[Bool] = @qc.Gen::spawn(); g.fmap(fn(b) { @jsonc.JsonNode::bool_with_trivia(b, empty) }) },
      gen_valid_number().fmap(fn(n) { @jsonc.JsonNode::number_with_trivia(n, empty) }),
      gen_safe_string().fmap(fn(s) { @jsonc.JsonNode::string_with_trivia(s, empty) }),
    ],
  )
}

///|
/// Generate a simple JsonNode with limited depth
fn gen_simple_json_node() -> @qc.Gen[@jsonc.JsonNode] {
  let empty = @common.Trivia::empty()
  // Use frequency to prefer scalars but allow some structure
  @qc.frequency(
    [
      // Scalars (high weight)
      (4, @qc.pure(@jsonc.JsonNode::null_with_trivia(empty))),
      (4, { let g : @qc.Gen[Bool] = @qc.Gen::spawn(); g.fmap(fn(b) { @jsonc.JsonNode::bool_with_trivia(b, empty) }) }),
      (4, gen_valid_number().fmap(fn(n) { @jsonc.JsonNode::number_with_trivia(n, empty) })),
      (4, gen_safe_string().fmap(fn(s) { @jsonc.JsonNode::string_with_trivia(s, empty) })),
      // Empty array
      (1, @qc.pure(@jsonc.JsonNode::array_with_trivia([], empty))),
      // Empty object
      (1, @qc.pure(@jsonc.JsonNode::object_with_trivia([], empty))),
      // Small array with scalars
      (
        1,
        gen_json_scalar().bind(fn(elem1) {
          gen_json_scalar().fmap(fn(elem2) { @jsonc.JsonNode::array_with_trivia([elem1, elem2], empty) })
        }),
      ),
      // Small object with scalars
      (
        1,
        gen_safe_key().bind(fn(key1) {
          gen_json_scalar().bind(fn(val1) {
            gen_safe_key().bind(fn(key2) {
              gen_json_scalar().fmap(fn(val2) {
                @jsonc.JsonNode::object_with_trivia(
                  [
                    @jsonc.JProperty::new(key1, empty, val1),
                    @jsonc.JProperty::new(key2, empty, val2),
                  ],
                  empty,
                )
              })
            })
          })
        }),
      ),
    ],
  )
}

///|
/// Generate a simple scalar YamlNode (no recursion)
fn gen_yaml_scalar() -> @qc.Gen[@yaml.YamlNode] {
  let empty = @common.Trivia::empty()
  @qc.one_of(
    [
      @qc.pure(@yaml.YamlNode::null_with_trivia(empty)),
      { let g : @qc.Gen[Bool] = @qc.Gen::spawn(); g.fmap(fn(b) { @yaml.YamlNode::bool_with_trivia(b, empty) }) },
      gen_valid_number().fmap(fn(n) { @yaml.YamlNode::number_with_trivia(n, empty) }),
      gen_safe_string().fmap(fn(s) {
        @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::double_quoted(), empty)
      }),
    ],
  )
}

///|
/// Generate a simple YamlNode with limited depth
fn gen_simple_yaml_node() -> @qc.Gen[@yaml.YamlNode] {
  let empty = @common.Trivia::empty()
  @qc.frequency(
    [
      // Scalars (high weight)
      (4, @qc.pure(@yaml.YamlNode::null_with_trivia(empty))),
      (4, { let g : @qc.Gen[Bool] = @qc.Gen::spawn(); g.fmap(fn(b) { @yaml.YamlNode::bool_with_trivia(b, empty) }) }),
      (4, gen_valid_number().fmap(fn(n) { @yaml.YamlNode::number_with_trivia(n, empty) })),
      (
        4,
        gen_safe_string().fmap(fn(s) {
          @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::double_quoted(), empty)
        }),
      ),
      // Empty sequence
      (1, @qc.pure(@yaml.YamlNode::sequence_with_trivia([], empty))),
      // Empty mapping
      (1, @qc.pure(@yaml.YamlNode::mapping_with_trivia([], empty))),
      // Small sequence with scalars
      (
        1,
        gen_yaml_scalar().bind(fn(elem1) {
          gen_yaml_scalar().fmap(fn(elem2) {
            @yaml.YamlNode::sequence_with_trivia([elem1, elem2], empty)
          })
        }),
      ),
      // Small mapping with scalars
      (
        1,
        gen_safe_key().bind(fn(key1) {
          gen_yaml_scalar().bind(fn(val1) {
            gen_safe_key().bind(fn(key2) {
              gen_yaml_scalar().fmap(fn(val2) {
                @yaml.YamlNode::mapping_with_trivia(
                  [
                    @yaml.YKeyValue::new(
                      @yaml.YamlNode::string_with_trivia(
                        key1,
                        @yaml.YamlScalarStyle::double_quoted(),
                        empty,
                      ),
                      empty,
                      val1,
                    ),
                    @yaml.YKeyValue::new(
                      @yaml.YamlNode::string_with_trivia(
                        key2,
                        @yaml.YamlScalarStyle::double_quoted(),
                        empty,
                      ),
                      empty,
                      val2,
                    ),
                  ],
                  empty,
                )
              })
            })
          })
        }),
      ),
    ],
  )
}

///|
/// PBT: JSONC print -> parse round-trip preserves structure
test "pbt_jsonc_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_simple_json_node(), fn(node) {
      let printed = @jsonc.print(node)
      match @jsonc.parse(printed) {
        Ok(parsed) => strip_jsonc_trivia(node) == strip_jsonc_trivia(parsed)
        Err(_) => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: YAML print -> parse round-trip preserves structure
test "pbt_yaml_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_simple_yaml_node(), fn(node) {
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(parsed) => strip_yaml_trivia(node) == strip_yaml_trivia(parsed)
        Err(_) => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: JSONC -> YAML -> JSONC transformation preserves structure
test "pbt_jsonc_yaml_jsonc_transform" {
  @qc.quick_check(
    @qc.forall(gen_simple_json_node(), fn(node) {
      // JSONC -> YAML
      let yaml_node = @transform.jsonc_to_yaml(node)
      // YAML -> JSONC
      let back = @transform.yaml_to_jsonc(yaml_node)
      // Compare structures (ignoring trivia)
      strip_jsonc_trivia(node) == strip_jsonc_trivia(back)
    }),
    max_success=100,
  )
}

///|
/// PBT: Full string round-trip JSONC -> YAML -> JSONC
test "pbt_string_roundtrip_jsonc_yaml_jsonc" {
  @qc.quick_check(
    @qc.forall(gen_simple_json_node(), fn(node) {
      let jsonc_str = @jsonc.print(node)
      match jsonc_to_yaml(jsonc_str) {
        Ok(yaml_str) =>
          match yaml_to_jsonc(yaml_str) {
            Ok(back_jsonc_str) =>
              match @jsonc.parse(back_jsonc_str) {
                Ok(back_node) =>
                  strip_jsonc_trivia(node) == strip_jsonc_trivia(back_node)
                Err(_) => false
              }
            Err(_) => false
          }
        Err(_) => false
      }
    }),
    max_success=100,
  )
}

///|
/// Generate nested JSON structure similar to GitHub Actions workflows
/// Tests deeply nested mappings with sequences
fn gen_nested_workflow_json() -> @qc.Gen[@jsonc.JsonNode] {
  let empty = @common.Trivia::empty()
  // Use gen_safe_key() for all string values to avoid YAML special chars
  gen_safe_key().bind(fn(job_name) {
    gen_safe_key().bind(fn(runs_on) {
      gen_safe_key().bind(fn(perm_key) {
        gen_safe_key().bind(fn(perm_val) {
          gen_safe_key().bind(fn(step_name) {
            gen_safe_key().fmap(fn(step_val) {
              // Structure: { jobs: { <job_name>: { runs-on: ..., permissions: {...}, steps: [...] } } }
              @jsonc.JsonNode::object_with_trivia(
                [
                  @jsonc.JProperty::new(
                    "jobs",
                    empty,
                    @jsonc.JsonNode::object_with_trivia(
                      [
                        @jsonc.JProperty::new(
                          job_name,
                          empty,
                          @jsonc.JsonNode::object_with_trivia(
                            [
                              @jsonc.JProperty::new(
                                "runson",
                                empty,
                                @jsonc.JsonNode::string_with_trivia(runs_on, empty),
                              ),
                              @jsonc.JProperty::new(
                                "permissions",
                                empty,
                                @jsonc.JsonNode::object_with_trivia(
                                  [
                                    @jsonc.JProperty::new(
                                      perm_key,
                                      empty,
                                      @jsonc.JsonNode::string_with_trivia(perm_val, empty),
                                    ),
                                  ],
                                  empty,
                                ),
                              ),
                              @jsonc.JProperty::new(
                                "steps",
                                empty,
                                @jsonc.JsonNode::array_with_trivia(
                                  [
                                    @jsonc.JsonNode::object_with_trivia(
                                      [
                                        @jsonc.JProperty::new(
                                          "name",
                                          empty,
                                          @jsonc.JsonNode::string_with_trivia(step_name, empty),
                                        ),
                                        @jsonc.JProperty::new(
                                          "uses",
                                          empty,
                                          @jsonc.JsonNode::string_with_trivia(step_val, empty),
                                        ),
                                      ],
                                      empty,
                                    ),
                                  ],
                                  empty,
                                ),
                              ),
                            ],
                            empty,
                          ),
                        ),
                      ],
                      empty,
                    ),
                  ),
                ],
                empty,
              )
            })
          })
        })
      })
    })
  })
}

///|
/// PBT: Nested workflow structure round-trip JSONC -> YAML -> JSONC
test "pbt_nested_workflow_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_nested_workflow_json(), fn(node) {
      let jsonc_str = @jsonc.print(node)
      match jsonc_to_yaml(jsonc_str) {
        Ok(yaml_str) =>
          match yaml_to_jsonc(yaml_str) {
            Ok(back_jsonc_str) =>
              match @jsonc.parse(back_jsonc_str) {
                Ok(back_node) =>
                  strip_jsonc_trivia(node) == strip_jsonc_trivia(back_node)
                Err(_) => false
              }
            Err(_) => false
          }
        Err(_) => false
      }
    }),
    max_success=100,
  )
}

// ============================================================================
// Phase 1: Trivia (Comment) Preservation Tests
// ============================================================================

///|
/// Generate safe comment text (no newlines, no */ for block comments)
fn gen_comment_text() -> @qc.Gen[String] {
  @qc.one_of(
    [
      @qc.pure("comment"),
      @qc.pure("TODO: fix this"),
      @qc.pure("Author: test"),
      @qc.pure("重要な項目"),
      @qc.pure("note: value"),
      gen_safe_string().fmap(fn(s) {
        // Filter out newlines and ensure no problematic sequences
        let buf = StringBuilder::new()
        for c in s {
          let code = c.to_int()
          if code >= 0x20 && code < 0x7f && c != '\n' && c != '\r' {
            buf.write_char(c)
          }
        }
        let result = buf.to_string()
        if result.is_empty() {
          "comment"
        } else {
          result
        }
      }),
    ],
  )
}

///|
/// Generate a line comment
fn gen_line_comment() -> @qc.Gen[@common.Comment] {
  let empty_span = @common.Span::at(@common.Pos::zero())
  gen_comment_text().fmap(fn(content) {
    @common.Comment::new(content, @common.CommentKind::line(), empty_span, false)
  })
}

///|
/// Generate a block comment
fn gen_block_comment() -> @qc.Gen[@common.Comment] {
  let empty_span = @common.Span::at(@common.Pos::zero())
  gen_comment_text().fmap(fn(content) {
    @common.Comment::new(content, @common.CommentKind::block(), empty_span, false)
  })
}

///|
/// Generate JSONC trivia (supports block and line comments)
fn gen_jsonc_trivia() -> @qc.Gen[@common.Trivia] {
  @qc.frequency(
    [
      // Most common: no comments
      (10, @qc.pure(@common.Trivia::empty())),
      // Single leading line comment
      (3, gen_line_comment().fmap(fn(c) { @common.Trivia::with_leading([c]) })),
      // Single leading block comment
      (2, gen_block_comment().fmap(fn(c) { @common.Trivia::with_leading([c]) })),
      // Single trailing line comment
      (2, gen_line_comment().fmap(fn(c) { @common.Trivia::with_trailing([c]) })),
      // Both leading and trailing
      (1, gen_line_comment().bind(fn(l) {
        gen_line_comment().fmap(fn(t) { @common.Trivia::new([l], [t]) })
      })),
    ],
  )
}

///|
/// Generate YAML trivia (only line comments)
fn gen_yaml_trivia() -> @qc.Gen[@common.Trivia] {
  @qc.frequency(
    [
      // Most common: no comments
      (10, @qc.pure(@common.Trivia::empty())),
      // Single leading comment
      (3, gen_line_comment().fmap(fn(c) { @common.Trivia::with_leading([c]) })),
      // Single trailing comment
      (2, gen_line_comment().fmap(fn(c) { @common.Trivia::with_trailing([c]) })),
      // Both leading and trailing
      (1, gen_line_comment().bind(fn(l) {
        gen_line_comment().fmap(fn(t) { @common.Trivia::new([l], [t]) })
      })),
    ],
  )
}

///|
/// Generate a JSON scalar with trivia attached
fn gen_json_scalar_with_trivia() -> @qc.Gen[@jsonc.JsonNode] {
  gen_jsonc_trivia().bind(fn(trivia) {
    @qc.one_of(
      [
        @qc.pure(@jsonc.JsonNode::null_with_trivia(trivia)),
        {
          let g : @qc.Gen[Bool] = @qc.Gen::spawn()
          g.fmap(fn(b) { @jsonc.JsonNode::bool_with_trivia(b, trivia) })
        },
        gen_valid_number().fmap(fn(n) { @jsonc.JsonNode::number_with_trivia(n, trivia) }),
        gen_safe_string().fmap(fn(s) { @jsonc.JsonNode::string_with_trivia(s, trivia) }),
      ],
    )
  })
}

///|
/// Generate a JSON node with trivia (limited depth)
fn gen_json_node_with_trivia() -> @qc.Gen[@jsonc.JsonNode] {
  @qc.frequency(
    [
      // Scalars (high weight)
      (6, gen_json_scalar_with_trivia()),
      // Empty array
      (1, gen_jsonc_trivia().fmap(fn(t) { @jsonc.JsonNode::array_with_trivia([], t) })),
      // Empty object
      (1, gen_jsonc_trivia().fmap(fn(t) { @jsonc.JsonNode::object_with_trivia([], t) })),
      // Small array with trivia
      (
        1,
        gen_json_scalar_with_trivia().bind(fn(elem) {
          gen_jsonc_trivia().fmap(fn(t) { @jsonc.JsonNode::array_with_trivia([elem], t) })
        }),
      ),
      // Small object with trivia
      (
        1,
        gen_safe_key().bind(fn(key) {
          gen_jsonc_trivia().bind(fn(key_trivia) {
            gen_json_scalar_with_trivia().fmap(fn(val) {
              @jsonc.JsonNode::object_with_trivia(
                [@jsonc.JProperty::new(key, key_trivia, val)],
                @common.Trivia::empty(),
              )
            })
          })
        }),
      ),
    ],
  )
}

///|
/// Generate a YAML scalar with trivia attached
fn gen_yaml_scalar_with_trivia() -> @qc.Gen[@yaml.YamlNode] {
  gen_yaml_trivia().bind(fn(trivia) {
    @qc.one_of(
      [
        @qc.pure(@yaml.YamlNode::null_with_trivia(trivia)),
        {
          let g : @qc.Gen[Bool] = @qc.Gen::spawn()
          g.fmap(fn(b) { @yaml.YamlNode::bool_with_trivia(b, trivia) })
        },
        gen_valid_number().fmap(fn(n) { @yaml.YamlNode::number_with_trivia(n, trivia) }),
        gen_safe_string().fmap(fn(s) {
          @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::double_quoted(), trivia)
        }),
      ],
    )
  })
}

///|
/// Generate a YAML node with trivia (limited depth)
fn gen_yaml_node_with_trivia() -> @qc.Gen[@yaml.YamlNode] {
  @qc.frequency(
    [
      // Scalars (high weight)
      (6, gen_yaml_scalar_with_trivia()),
      // Empty sequence
      (1, gen_yaml_trivia().fmap(fn(t) { @yaml.YamlNode::sequence_with_trivia([], t) })),
      // Empty mapping
      (1, gen_yaml_trivia().fmap(fn(t) { @yaml.YamlNode::mapping_with_trivia([], t) })),
      // Small sequence with trivia
      (
        1,
        gen_yaml_scalar_with_trivia().bind(fn(elem) {
          gen_yaml_trivia().fmap(fn(t) { @yaml.YamlNode::sequence_with_trivia([elem], t) })
        }),
      ),
      // Small mapping with trivia
      (
        1,
        gen_safe_key().bind(fn(key) {
          gen_yaml_trivia().bind(fn(key_trivia) {
            gen_yaml_scalar_with_trivia().fmap(fn(val) {
              @yaml.YamlNode::mapping_with_trivia(
                [@yaml.YKeyValue::new(
                  @yaml.YamlNode::string_with_trivia(
                    key,
                    @yaml.YamlScalarStyle::double_quoted(),
                    @common.Trivia::empty(),
                  ),
                  key_trivia,
                  val,
                )],
                @common.Trivia::empty(),
              )
            })
          })
        }),
      ),
    ],
  )
}

///|
/// Extract all comments from a JsonNode recursively
fn extract_jsonc_comments(node : @jsonc.JsonNode) -> Array[@common.Comment] {
  let comments : Array[@common.Comment] = []
  collect_jsonc_comments(node, comments)
  comments
}

///|
/// Collect comments from JsonNode into accumulator
fn collect_jsonc_comments(node : @jsonc.JsonNode, acc : Array[@common.Comment]) -> Unit {
  let trivia = node.trivia()
  acc.push_iter(trivia.leading.iter())
  acc.push_iter(trivia.trailing.iter())
  match node {
    @jsonc.JArray(elements, _) => {
      for e in elements {
        collect_jsonc_comments(e, acc)
      }
    }
    @jsonc.JObject(props, _) => {
      for p in props {
        acc.push_iter(p.key_trivia.leading.iter())
        acc.push_iter(p.key_trivia.trailing.iter())
        collect_jsonc_comments(p.value, acc)
      }
    }
    _ => ()
  }
}

///|
/// Extract all comments from a YamlNode recursively
fn extract_yaml_comments(node : @yaml.YamlNode) -> Array[@common.Comment] {
  let comments : Array[@common.Comment] = []
  collect_yaml_comments(node, comments)
  comments
}

///|
/// Collect comments from YamlNode into accumulator
fn collect_yaml_comments(node : @yaml.YamlNode, acc : Array[@common.Comment]) -> Unit {
  let trivia = node.trivia()
  acc.push_iter(trivia.leading.iter())
  acc.push_iter(trivia.trailing.iter())
  match node {
    @yaml.YSequence(elements, _, _) => {
      for e in elements {
        collect_yaml_comments(e, acc)
      }
    }
    @yaml.YMapping(pairs, _, _) => {
      for kv in pairs {
        acc.push_iter(kv.key_trivia.leading.iter())
        acc.push_iter(kv.key_trivia.trailing.iter())
        collect_yaml_comments(kv.key, acc)
        collect_yaml_comments(kv.value, acc)
      }
    }
    @yaml.YAnchor(_, inner) => {
      collect_yaml_comments(inner, acc)
    }
    _ => ()
  }
}

///|
/// Normalize comment content for comparison
fn normalize_comment_content(comments : Array[@common.Comment]) -> Array[String] {
  let result : Array[String] = []
  for c in comments {
    let trimmed = c.content.trim()
    if not(trimmed.is_empty()) {
      result.push(trimmed.to_string())
    }
  }
  result
}

///|
/// PBT: JSONC comments are preserved through print -> parse round-trip
test "pbt_jsonc_trivia_preserved_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_json_node_with_trivia(), fn(node) {
      let printed = @jsonc.print(node)
      match @jsonc.parse(printed) {
        Ok(parsed) => {
          let original_comments = normalize_comment_content(extract_jsonc_comments(node))
          let parsed_comments = normalize_comment_content(extract_jsonc_comments(parsed))
          original_comments == parsed_comments
        }
        Err(_) => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: YAML comments are preserved through print -> parse round-trip
test "pbt_yaml_trivia_preserved_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_yaml_node_with_trivia(), fn(node) {
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(parsed) => {
          let original_comments = normalize_comment_content(extract_yaml_comments(node))
          let parsed_comments = normalize_comment_content(extract_yaml_comments(parsed))
          original_comments == parsed_comments
        }
        Err(_) => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: Comments content is preserved through JSONC -> YAML transformation
/// Note: Block comments become multiple line comments in YAML
test "pbt_jsonc_to_yaml_trivia_preserved" {
  @qc.quick_check(
    @qc.forall(gen_json_node_with_trivia(), fn(node) {
      let yaml_node = @transform.jsonc_to_yaml(node)
      let original_comments = normalize_comment_content(extract_jsonc_comments(node))
      let yaml_comments = normalize_comment_content(extract_yaml_comments(yaml_node))
      // Comment content should be preserved (block -> line splits are OK)
      // Check that all original comment content appears in YAML comments
      let all_found = {
        let mut found = true
        for orig in original_comments {
          let mut current_found = false
          for y in yaml_comments {
            if string_contains(y, orig) || string_contains(orig, y) {
              current_found = true
            }
          }
          if not(current_found) {
            found = false
          }
        }
        found
      }
      all_found
    }),
    max_success=100,
  )
}

///|
/// Helper: check if a string contains another string
fn string_contains(haystack : String, needle : String) -> Bool {
  if needle.length() > haystack.length() {
    false
  } else {
    let haystack_chars = haystack.to_array()
    let needle_chars = needle.to_array()
    // Check if needle_chars appears in haystack_chars
    let mut found = false
    let mut i = 0
    while i <= haystack_chars.length() - needle_chars.length() && not(found) {
      let mut is_match = true
      let mut j = 0
      while j < needle_chars.length() && is_match {
        if haystack_chars[i + j] != needle_chars[j] {
          is_match = false
        } else {
          j = j + 1
        }
      }
      if is_match {
        found = true
      } else {
        i = i + 1
      }
    }
    found
  }
}

///|
/// PBT: Comments content is preserved through YAML -> JSONC transformation
test "pbt_yaml_to_jsonc_trivia_preserved" {
  @qc.quick_check(
    @qc.forall(gen_yaml_node_with_trivia(), fn(node) {
      let jsonc_node = @transform.yaml_to_jsonc(node)
      let original_comments = normalize_comment_content(extract_yaml_comments(node))
      let jsonc_comments = normalize_comment_content(extract_jsonc_comments(jsonc_node))
      original_comments == jsonc_comments
    }),
    max_success=100,
  )
}

// ============================================================================
// Phase 2: Edge Cases Tests
// ============================================================================

///|
/// Generate Japanese strings
fn gen_japanese_string() -> @qc.Gen[String] {
  @qc.one_of(
    [
      @qc.pure("こんにちは"),
      @qc.pure("日本語テスト"),
      @qc.pure("カタカナ"),
      @qc.pure("漢字混じり文字列"),
      @qc.pure("全角数字１２３"),
      @qc.pure("😀絵文字も含む"),
    ],
  )
}

///|
/// Generate emoji strings
fn gen_emoji_string() -> @qc.Gen[String] {
  @qc.one_of(
    [
      @qc.pure("Hello 👋 World"),
      @qc.pure("🎉 Celebration 🎊"),
      @qc.pure("❤️ Love ❤️"),
      @qc.pure("🚀 Rocket 🌟"),
      @qc.pure("🏳️‍🌈 Pride"),
      @qc.pure("test with 😊 emoji"),
    ],
  )
}

///|
/// Generate Unicode strings from various scripts
fn gen_unicode_string() -> @qc.Gen[String] {
  @qc.frequency(
    [
      (3, gen_safe_string()),  // ASCII baseline
      (2, gen_japanese_string()),
      (2, gen_emoji_string()),
      (1, @qc.pure("中文测试")),
      (1, @qc.pure("한국어 테스트")),
      (1, @qc.pure("العربية")),
    ],
  )
}

///|
/// Generate strings that need escaping in JSON
fn gen_escape_needed_string() -> @qc.Gen[String] {
  @qc.one_of(
    [
      @qc.pure("line1\nline2"),
      @qc.pure("tab\there"),
      @qc.pure("quote\"inside"),
      @qc.pure("backslash\\path"),
      @qc.pure("mixed\"\n\\tabs"),
    ],
  )
}

///|
/// Generate strings that look like YAML keywords
fn gen_yaml_keyword_like_string() -> @qc.Gen[String] {
  @qc.one_of(
    [
      @qc.pure("null"),
      @qc.pure("Null"),
      @qc.pure("NULL"),
      @qc.pure("true"),
      @qc.pure("True"),
      @qc.pure("TRUE"),
      @qc.pure("false"),
      @qc.pure("False"),
      @qc.pure("FALSE"),
      @qc.pure("yes"),
      @qc.pure("no"),
      @qc.pure("on"),
      @qc.pure("off"),
    ],
  )
}

///|
/// Generate edge case numbers
fn gen_edge_case_number() -> @qc.Gen[String] {
  @qc.one_of(
    [
      @qc.pure("0"),
      @qc.pure("-0"),
      @qc.pure("9999999999999999"),
      @qc.pure("-9999999999999999"),
      @qc.pure("1e10"),
      @qc.pure("1E10"),
      @qc.pure("1e+10"),
      @qc.pure("1e-10"),
      @qc.pure("1.5e10"),
      @qc.pure("1.5E-10"),
      @qc.pure("0.1"),
      @qc.pure("3.141592653589793"),
    ],
  )
}

///|
/// Generate deeply nested JSON structures
fn gen_deeply_nested_json(max_depth : Int) -> @qc.Gen[@jsonc.JsonNode] {
  @qc.sized(fn(size) {
    let depth = (size / 10).clamp(min=1, max=max_depth)
    gen_nested_json_at_depth(depth, @common.Trivia::empty())
  })
}

///|
/// Generate nested JSON at specific depth
fn gen_nested_json_at_depth(depth : Int, trivia : @common.Trivia) -> @qc.Gen[@jsonc.JsonNode] {
  if depth <= 0 {
    gen_json_scalar()
  } else {
    @qc.frequency(
      [
        // Nested array
        (
          1,
          gen_nested_json_at_depth(depth - 1, @common.Trivia::empty()).fmap(fn(inner) {
            @jsonc.JsonNode::array_with_trivia([inner], trivia)
          }),
        ),
        // Nested object
        (
          1,
          gen_safe_key().bind(fn(key) {
            gen_nested_json_at_depth(depth - 1, @common.Trivia::empty()).fmap(fn(inner) {
              @jsonc.JsonNode::object_with_trivia(
                [@jsonc.JProperty::new(key, @common.Trivia::empty(), inner)],
                trivia,
              )
            })
          }),
        ),
      ],
    )
  }
}

///|
/// Generate empty/edge case JSON values
fn gen_empty_json() -> @qc.Gen[@jsonc.JsonNode] {
  let empty = @common.Trivia::empty()
  @qc.one_of(
    [
      @qc.pure(@jsonc.JsonNode::string_with_trivia("", empty)),  // Empty string
      @qc.pure(@jsonc.JsonNode::array_with_trivia([], empty)),   // Empty array
      @qc.pure(@jsonc.JsonNode::object_with_trivia([], empty)),  // Empty object
      @qc.pure(@jsonc.JsonNode::null_with_trivia(empty)),        // Null
    ],
  )
}

///|
/// PBT: Unicode strings survive JSONC round-trip
test "pbt_unicode_jsonc_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_unicode_string(), fn(s) {
      let node = @jsonc.JsonNode::string(s)
      let printed = @jsonc.print(node)
      match @jsonc.parse(printed) {
        Ok(@jsonc.JString(parsed_s, _)) => s == parsed_s
        _ => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: Unicode strings survive YAML round-trip
test "pbt_unicode_yaml_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_unicode_string(), fn(s) {
      let node = @yaml.YamlNode::string(s, @yaml.YamlScalarStyle::double_quoted())
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(@yaml.YString(parsed_s, _, _)) => s == parsed_s
        _ => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: Unicode strings survive JSONC -> YAML -> JSONC transformation
test "pbt_unicode_transform_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_unicode_string(), fn(s) {
      let json_node = @jsonc.JsonNode::string(s)
      let yaml_node = @transform.jsonc_to_yaml(json_node)
      let back = @transform.yaml_to_jsonc(yaml_node)
      match back {
        @jsonc.JString(result, _) => s == result
        _ => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: Special escape sequences are preserved in JSONC round-trip
test "pbt_escape_chars_jsonc_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_escape_needed_string(), fn(s) {
      let node = @jsonc.JsonNode::string(s)
      let printed = @jsonc.print(node)
      match @jsonc.parse(printed) {
        Ok(@jsonc.JString(parsed, _)) => s == parsed
        _ => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: YAML keyword-like strings are properly quoted and preserved
test "pbt_yaml_keyword_strings_preserved" {
  @qc.quick_check(
    @qc.forall(gen_yaml_keyword_like_string(), fn(s) {
      let node = @yaml.YamlNode::string(s, @yaml.YamlScalarStyle::double_quoted())
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(@yaml.YString(parsed, _, _)) => s == parsed
        _ => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: Deeply nested structures survive JSONC round-trip
test "pbt_deep_nesting_jsonc_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_deeply_nested_json(10), fn(node) {
      let printed = @jsonc.print(node)
      match @jsonc.parse(printed) {
        Ok(parsed) => strip_jsonc_trivia(node) == strip_jsonc_trivia(parsed)
        Err(_) => false
      }
    }),
    max_success=50,
  )
}

///|
/// PBT: Deeply nested structures survive transformation round-trip
test "pbt_deep_nesting_transform_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_deeply_nested_json(8), fn(node) {
      let yaml = @transform.jsonc_to_yaml(node)
      let back = @transform.yaml_to_jsonc(yaml)
      strip_jsonc_trivia(node) == strip_jsonc_trivia(back)
    }),
    max_success=50,
  )
}

///|
/// PBT: Empty values are handled correctly in JSONC round-trip
test "pbt_empty_values_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_empty_json(), fn(node) {
      let printed = @jsonc.print(node)
      match @jsonc.parse(printed) {
        Ok(parsed) => strip_jsonc_trivia(node) == strip_jsonc_trivia(parsed)
        Err(_) => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: Edge case numbers are preserved in JSONC round-trip
test "pbt_edge_case_numbers" {
  @qc.quick_check(
    @qc.forall(gen_edge_case_number(), fn(num_str) {
      let node = @jsonc.JsonNode::number(num_str)
      let printed = @jsonc.print(node)
      match @jsonc.parse(printed) {
        Ok(@jsonc.JNumber(parsed, _)) => num_str == parsed
        _ => false
      }
    }),
    max_success=100,
  )
}

// ============================================================================
// Position Mapping Tests
// ============================================================================

///|
/// Unit test: Empty mappings return None for lookup
test "mapping_lookup_empty_returns_none" {
  let mappings : Array[@common.SourceMapping] = []
  let result = @common.lookup_target_position(mappings, 0, 0, 0)
  match result {
    None => assert_true(true)
    Some(_) => assert_false(true)
  }
}

///|
/// Unit test: Lookup finds exact match
test "mapping_lookup_exact_match" {
  let start = @common.Pos::new(0, 0, 0)
  let end = @common.Pos::new(0, 5, 5)
  let target_start = @common.Pos::new(1, 2, 10)
  let target_end = @common.Pos::new(1, 7, 15)

  let mapping = @common.SourceMapping::new(start, end, target_start, target_end)
  let mappings = [mapping]

  // Position at offset 2 should match
  let result = @common.lookup_target_position(mappings, 0, 2, 2)
  match result {
    Some(pos) => assert_true(pos == target_start)
    None => assert_false(true)
  }
}

///|
/// Unit test: Lookup returns None for position outside range
test "mapping_lookup_outside_range_returns_none" {
  let start = @common.Pos::new(0, 0, 0)
  let end = @common.Pos::new(0, 5, 5)
  let target_start = @common.Pos::new(1, 2, 10)
  let target_end = @common.Pos::new(1, 7, 15)

  let mapping = @common.SourceMapping::new(start, end, target_start, target_end)
  let mappings = [mapping]

  // Position at offset 10 should not match
  let result = @common.lookup_target_position(mappings, 0, 10, 10)
  match result {
    None => assert_true(true)
    Some(_) => assert_false(true)
  }
}

///|
/// Unit test: Reverse lookup (target to source)
test "mapping_reverse_lookup" {
  let source_start = @common.Pos::new(0, 0, 0)
  let source_end = @common.Pos::new(0, 5, 5)
  let target_start = @common.Pos::new(1, 2, 10)
  let target_end = @common.Pos::new(1, 7, 15)

  let mapping = @common.SourceMapping::new(source_start, source_end, target_start, target_end)
  let mappings = [mapping]

  // Position in target should map back to source
  let result = @common.lookup_source_position(mappings, 1, 5, 12)
  match result {
    Some(pos) => assert_true(pos == source_start)
    None => assert_false(true)
  }
}

///|
/// Unit test: ConversionResult creation
test "mapping_conversion_result_creation" {
  let output = "test output"
  let mappings : Array[@common.SourceMapping] = []

  let result = @common.ConversionResult::new(output, mappings)
  let output_match = result.output == output
  let mappings_empty = result.mappings.length() == 0
  assert_true(output_match && mappings_empty)
}

///|
/// Unit test: Empty conversion result
test "mapping_empty_conversion_result" {
  let result = @common.ConversionResult::empty()
  let output_empty = result.output == ""
  let mappings_empty = result.mappings.length() == 0
  assert_true(output_empty && mappings_empty)
}

///|
/// PBT: Lookup is consistent with mapping range
test "pbt_mapping_lookup_consistency" {
  // Generator for a position with small offset values
  let gen_small_pos : @qc.Gen[@common.Pos] = @qc.Gen::spawn()
  let gen_pos = gen_small_pos.fmap(fn(p) {
    @common.Pos::new(0, 0, p.offset % 50)
  })

  // Generator for small positive integers (1-100)
  let gen_int : @qc.Gen[Int] = @qc.Gen::spawn()
  let gen_small_int = gen_int.fmap(fn(n) {
    let abs_n = if n < 0 { -n } else { n }
    1 + (abs_n % 100)
  })

  let gen_mapping = gen_pos.bind(fn(start) {
    gen_small_int.fmap(fn(delta) {
      let end_offset = start.offset + delta
      let end = @common.Pos::new(start.line + 1, 0, end_offset)
      let target_start = @common.Pos::new(10, 0, 200)
      let target_end = @common.Pos::new(10, 5, 205)
      @common.SourceMapping::new(start, end, target_start, target_end)
    })
  })

  @qc.quick_check(
    @qc.forall(gen_mapping, fn(mapping) {
      let mappings = [mapping]

      // Position at start should be found
      let start_result = @common.lookup_target_position(
        mappings,
        mapping.source_start.line,
        mapping.source_start.column,
        mapping.source_start.offset,
      )

      match start_result {
        Some(pos) => pos == mapping.target_start
        None => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: Source and target lookup are inverses
test "pbt_mapping_lookup_roundtrip" {
  // Generator for a position with small offset values
  let gen_small_pos : @qc.Gen[@common.Pos] = @qc.Gen::spawn()
  let gen_pos = gen_small_pos.fmap(fn(p) {
    @common.Pos::new(0, 0, p.offset % 50)
  })

  // Generator for small positive integers (1-100)
  let gen_int : @qc.Gen[Int] = @qc.Gen::spawn()
  let gen_small_int = gen_int.fmap(fn(n) {
    let abs_n = if n < 0 { -n } else { n }
    1 + (abs_n % 100)
  })

  let gen_mapping = gen_pos.bind(fn(start) {
    gen_small_int.fmap(fn(delta) {
      let end_offset = start.offset + delta
      let end = @common.Pos::new(start.line + 1, 0, end_offset)
      let target_start = @common.Pos::new(10, 0, 200)
      let target_end = @common.Pos::new(10, 5, 205)
      @common.SourceMapping::new(start, end, target_start, target_end)
    })
  })

  @qc.quick_check(
    @qc.forall(gen_mapping, fn(mapping) {
      let mappings = [mapping]

      // Source -> Target -> Source should give original position
      let target_result = @common.lookup_target_position(
        mappings,
        mapping.source_start.line,
        mapping.source_start.column,
        mapping.source_start.offset,
      )

      match target_result {
        Some(target_pos) => {
          let source_result = @common.lookup_source_position(
            mappings,
            target_pos.line,
            target_pos.column,
            target_pos.offset,
          )
          match source_result {
            Some(source_pos) => source_pos == mapping.source_start
            None => false
          }
        }
        None => false
      }
    }),
    max_success=100,
  )
}

// ============================================================================
// Phase 3: Large File Tests
// ============================================================================

///|
/// Generate a wide JSON object with many keys (simulates Kubernetes manifests)
fn gen_wide_json_object(num_keys : Int) -> @qc.Gen[@jsonc.JsonNode] {
  @qc.sized(fn(size) {
    let actual_keys = (size * num_keys / 10).clamp(min=10, max=num_keys)
    let empty = @common.Trivia::empty()
    // Generate scalar values for each key (memory efficient)
    let properties : Array[@jsonc.JProperty] = []
    let mut i = 0
    while i < actual_keys {
      let key = "key_" + i.to_string()
      properties.push(@jsonc.JProperty::new(key, empty, @jsonc.JsonNode::string_with_trivia("value", empty)))
      i = i + 1
    }
    @qc.pure(@jsonc.JsonNode::object_with_trivia(properties, empty))
  })
}

///|
/// Generate a long JSON array with many elements
fn gen_long_json_array(num_elements : Int) -> @qc.Gen[@jsonc.JsonNode] {
  @qc.sized(fn(size) {
    let actual_len = (size * num_elements / 10).clamp(min=10, max=num_elements)
    let empty = @common.Trivia::empty()
    let elements : Array[@jsonc.JsonNode] = []
    let mut i = 0
    while i < actual_len {
      elements.push(@jsonc.JsonNode::string_with_trivia("item_" + i.to_string(), empty))
      i = i + 1
    }
    @qc.pure(@jsonc.JsonNode::array_with_trivia(elements, empty))
  })
}

///|
/// Generate a mixed-size JSON with configurable depth and width
fn gen_mixed_size_json(depth : Int, width : Int) -> @qc.Gen[@jsonc.JsonNode] {
  let empty = @common.Trivia::empty()
  gen_mixed_json_at_depth(depth, width, empty)
}

///|
/// Helper: Generate mixed JSON at specific depth
fn gen_mixed_json_at_depth(depth : Int, width : Int, trivia : @common.Trivia) -> @qc.Gen[@jsonc.JsonNode] {
  if depth <= 0 {
    gen_json_scalar()
  } else {
    @qc.frequency(
      [
        // Nested array with width elements
        (
          1,
          @qc.sized(fn(size) {
            let actual_width = (size * width / 10).clamp(min=2, max=width)
            let elements : Array[@jsonc.JsonNode] = []
            let mut i = 0
            while i < actual_width {
              elements.push(@jsonc.JsonNode::string_with_trivia("item", @common.Trivia::empty()))
              i = i + 1
            }
            gen_mixed_json_at_depth(depth - 1, width, @common.Trivia::empty()).fmap(fn(inner) {
              elements.push(inner)
              @jsonc.JsonNode::array_with_trivia(elements, trivia)
            })
          }),
        ),
        // Nested object with width keys
        (
          1,
          @qc.sized(fn(size) {
            let actual_width = (size * width / 10).clamp(min=2, max=width)
            let properties : Array[@jsonc.JProperty] = []
            let mut i = 0
            while i < actual_width {
              properties.push(@jsonc.JProperty::new(
                "key_" + i.to_string(),
                @common.Trivia::empty(),
                @jsonc.JsonNode::string_with_trivia("value", @common.Trivia::empty()),
              ))
              i = i + 1
            }
            gen_mixed_json_at_depth(depth - 1, width, @common.Trivia::empty()).fmap(fn(inner) {
              properties.push(@jsonc.JProperty::new(
                "nested",
                @common.Trivia::empty(),
                inner,
              ))
              @jsonc.JsonNode::object_with_trivia(properties, trivia)
            })
          }),
        ),
        // Scalar at this level
        (4, gen_json_scalar()),
      ],
    )
  }
}

///|
/// Generate a string with approximately target_bytes size
fn gen_string_with_size(target_bytes : Int) -> @qc.Gen[String] {
  @qc.pure({
    let result = StringBuilder::new()
    let chunk = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    let chunk_len = chunk.length()
    let remaining = target_bytes
    let mut i = 0
    while i < remaining {
      result.write_string(chunk)
      i = i + chunk_len
    }
    result.to_string()
  })
}

///|
/// PBT: Wide objects (many keys) survive JSONC round-trip
test "pbt_large_wide_object_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_wide_json_object(500), fn(node) {
      let printed = @jsonc.print(node)
      match @jsonc.parse(printed) {
        Ok(parsed) => strip_jsonc_trivia(node) == strip_jsonc_trivia(parsed)
        Err(_) => false
      }
    }),
    max_success=20,
  )
}

///|
/// PBT: Long arrays survive JSONC round-trip
test "pbt_large_array_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_long_json_array(1000), fn(node) {
      let printed = @jsonc.print(node)
      match @jsonc.parse(printed) {
        Ok(parsed) => strip_jsonc_trivia(node) == strip_jsonc_trivia(parsed)
        Err(_) => false
      }
    }),
    max_success=20,
  )
}

///|
/// PBT: Mixed size structures survive transformation round-trip
test "pbt_mixed_size_stress_test" {
  @qc.quick_check(
    @qc.forall(gen_mixed_size_json(5, 50), fn(node) {
      let yaml_node = @transform.jsonc_to_yaml(node)
      let back = @transform.yaml_to_jsonc(yaml_node)
      strip_jsonc_trivia(node) == strip_jsonc_trivia(back)
    }),
    max_success=15,
  )
}

///|
/// PBT: Large strings survive JSONC round-trip
test "pbt_large_string_handling" {
  @qc.quick_check(
    @qc.forall(gen_string_with_size(10000), fn(s) {
      let node = @jsonc.JsonNode::string(s)
      let printed = @jsonc.print(node)
      match @jsonc.parse(printed) {
        Ok(@jsonc.JString(parsed, _)) => s == parsed
        _ => false
      }
    }),
    max_success=15,
  )
}

// ============================================================================
// Phase 1: YAML Anchor and Alias Generators
// ============================================================================

///|
/// Generate a valid YAML anchor name
/// YAML 1.2 spec: anchor names must start with alphanumeric or underscore,
/// and can contain alphanumeric, underscore, and hyphen
fn gen_anchor_name() -> @qc.Gen[String] {
  // Generate first char (must be alphanumeric or underscore, not hyphen)
  let gen_first : @qc.Gen[Char] = @qc.one_of([
    @qc.pure('_'),
    gen_char_range('a', 'z'),
    gen_char_range('A', 'Z'),
  ])

  // Generate rest of name character set
  let _gen_rest : @qc.Gen[Char] = @qc.one_of([
    @qc.pure('_'),
    @qc.pure('-'),
    gen_char_range('a', 'z'),
    gen_char_range('A', 'Z'),
    gen_char_range('0', '9'),
  ])

  @qc.sized(fn(size) {
    let name_len = (size / 5).clamp(min=1, max=20)

    // Generate first character
    gen_first.bind(fn(first) {
      // Generate rest of name (name_len - 1 characters)
      gen_rest_chars(name_len - 1).fmap(fn(rest) {
        let buf = StringBuilder::new()
        buf.write_char(first)
        for c in rest {
          buf.write_char(c)
        }
        buf.to_string()
      })
    })
  })
}

///|
/// Helper: generate a character in a range (inclusive)
fn gen_char_range(lo : Char, hi : Char) -> @qc.Gen[Char] {
  let gen_int : @qc.Gen[Int] = @qc.Gen::spawn()
  gen_int.fmap(fn(n) {
    let lo_code = lo.to_int()
    let hi_code = hi.to_int()
    let range = hi_code - lo_code + 1
    let offset = (n % range).abs()
    match (lo_code + offset).to_char() {
      Some(c) => c
      None => lo
    }
  })
}

///|
/// Helper: generate an array of characters with specific length
fn gen_rest_chars(count : Int) -> @qc.Gen[Array[Char]] {
  if count <= 0 {
    @qc.pure([])
  } else {
    let gen_rest : @qc.Gen[Char] = @qc.one_of([
      @qc.pure('_'),
      @qc.pure('-'),
      gen_char_range('a', 'z'),
      gen_char_range('A', 'Z'),
      gen_char_range('0', '9'),
    ])
    gen_rest.bind(fn(first) {
      gen_rest_chars(count - 1).fmap(fn(rest) {
        [first] + rest
      })
    })
  }
}

///|
/// Generate a YAnchor node with a valid anchor name
/// Creates an anchor definition: &name value
fn gen_yaml_anchor(inner_gen : @qc.Gen[@yaml.YamlNode]) -> @qc.Gen[@yaml.YamlNode] {
  gen_anchor_name().bind(fn(name) {
    inner_gen.fmap(fn(inner) {
      @yaml.YamlNode::anchor(name, inner)
    })
  })
}

///|
/// Generate a YAlias node that references an existing anchor
/// If no anchors are defined, returns a null node as fallback
fn gen_yaml_alias(defined_anchors : Array[String]) -> @qc.Gen[@yaml.YamlNode] {
  if defined_anchors.is_empty() {
    // Fallback: return a null node
    @qc.pure(@yaml.YamlNode::null_with_trivia(@common.Trivia::empty()))
  } else {
    // Select an existing anchor name uniformly
    gen_anchor_from_list(defined_anchors).fmap(fn(name) {
      @yaml.YamlNode::alias_with_trivia(name, @common.Trivia::empty())
    })
  }
}

///|
/// Helper: select an anchor name from the list uniformly
fn gen_anchor_from_list(anchors : Array[String]) -> @qc.Gen[String] {
  let gen_int : @qc.Gen[Int] = @qc.Gen::spawn()
  gen_int.fmap(fn(n) {
    let index = n.abs() % anchors.length()
    anchors[index]
  })
}

///|
/// Generate a YAML node with anchors and aliases (stateful version)
/// Returns a tuple of (node, array of defined anchor names)
fn gen_yaml_node_with_anchors_internal(max_depth : Int) -> @qc.Gen[(@yaml.YamlNode, Array[String])] {
  if max_depth <= 0 {
    // Base case: generate scalars, optionally with anchor
    @qc.frequency([
      // Scalar without anchor (most common)
      (4, gen_yaml_scalar_with_any_style().fmap(fn(n) { (n, []) })),
      // Scalar with anchor
      (1, gen_yaml_anchor(gen_yaml_scalar_with_any_style()).fmap(fn(n) {
        match n {
          @yaml.YAnchor(name, _) => (n, [name])
          _ => (n, [])
        }
      })),
    ])
  } else {
    // Recursive case: can include sequences, mappings, anchors, aliases
    @qc.frequency([
      // Scalar without anchor
      (3, gen_yaml_scalar_with_any_style().fmap(fn(n) { (n, []) })),

      // Scalar with anchor
      (1, gen_yaml_anchor(gen_yaml_scalar_with_any_style()).fmap(fn(n) {
        match n {
          @yaml.YAnchor(name, _) => (n, [name])
          _ => (n, [])
        }
      })),

      // Sequences with anchor tracking
      (2, gen_yaml_sequence_with_anchors(max_depth - 1)),

      // Mappings with anchor tracking
      (2, gen_yaml_mapping_with_anchors(max_depth - 1)),
    ])
  }
}

///|
/// Generate a YAML node with anchors and aliases (external API)
/// Wrapper that discards the state for use in @qc.forall
fn gen_yaml_node_with_anchor_alias() -> @qc.Gen[@yaml.YamlNode] {
  gen_yaml_node_with_anchors_internal(3).fmap(fn(result) {
    let (node, _anchors) = result
    node
  })
}

///|
/// Generate a sequence that may contain anchored elements
/// Returns (sequence_node, defined_anchor_names)
fn gen_yaml_sequence_with_anchors(depth : Int) -> @qc.Gen[(@yaml.YamlNode, Array[String])] {
  @qc.sized(fn(size) {
    let len = (size / 3).clamp(min=0, max=5)
    gen_yaml_sequence_with_anchors_at_length(len, depth)
  })
}

///|
/// Helper: Generate sequence of specific length with anchor tracking
fn gen_yaml_sequence_with_anchors_at_length(len : Int, depth : Int) -> @qc.Gen[(@yaml.YamlNode, Array[String])] {
  if len == 0 {
    @qc.pure((@yaml.YamlNode::sequence_with_trivia([], @common.Trivia::empty()), []))
  } else {
    // Generate first element with state
    gen_yaml_node_with_anchors_internal(depth).bind(fn(first_result) {
      let (first_elem, first_anchors) = first_result

      // Generate remaining elements, accumulating state
      gen_yaml_sequence_elements_with_state(len - 1, depth, first_anchors).fmap(fn(rest_result) {
        let (rest_elems, all_anchors) = rest_result
        let all_elems = [first_elem] + rest_elems
        (@yaml.YamlNode::sequence_with_trivia(all_elems, @common.Trivia::empty()), all_anchors)
      })
    })
  }
}

///|
/// Generate remaining sequence elements with accumulated anchor state
fn gen_yaml_sequence_elements_with_state(count : Int, depth : Int, anchors : Array[String]) -> @qc.Gen[(Array[@yaml.YamlNode], Array[String])] {
  if count == 0 {
    @qc.pure(([], anchors))
  } else {
    @qc.frequency([
      // Regular node (may define new anchors)
      (3, gen_yaml_node_with_anchors_internal(depth).bind(fn(result) {
        let (node, new_anchors) = result
        let combined_anchors = array_concat(anchors, new_anchors)
        gen_yaml_sequence_elements_with_state(count - 1, depth, combined_anchors).fmap(fn(rest) {
          let (rest_elems, final_anchors) = rest
          ([node] + rest_elems, final_anchors)
        })
      })),

      // Alias to existing anchor (if anchors available)
      (1, if anchors.is_empty() {
        // No anchors yet, generate regular node instead
        gen_yaml_node_with_anchors_internal(depth).bind(fn(result) {
          let (node, new_anchors) = result
          let combined_anchors = array_concat(anchors, new_anchors)
          gen_yaml_sequence_elements_with_state(count - 1, depth, combined_anchors).fmap(fn(rest) {
            let (rest_elems, final_anchors) = rest
            ([node] + rest_elems, final_anchors)
          })
        })
      } else {
        gen_yaml_alias(anchors).bind(fn(alias_node) {
          gen_yaml_sequence_elements_with_state(count - 1, depth, anchors).fmap(fn(rest) {
            let (rest_elems, final_anchors) = rest
            ([alias_node] + rest_elems, final_anchors)
          })
        })
      }),
    ])
  }
}

///|
/// Generate a mapping that may contain anchored values
/// Returns (mapping_node, defined_anchor_names)
fn gen_yaml_mapping_with_anchors(depth : Int) -> @qc.Gen[(@yaml.YamlNode, Array[String])] {
  @qc.sized(fn(size) {
    let len = (size / 4).clamp(min=0, max=4)
    gen_yaml_mapping_with_anchors_at_length(len, depth)
  })
}

///|
/// Helper: Generate mapping of specific length with anchor tracking
fn gen_yaml_mapping_with_anchors_at_length(len : Int, depth : Int) -> @qc.Gen[(@yaml.YamlNode, Array[String])] {
  if len == 0 {
    @qc.pure((@yaml.YamlNode::mapping_with_trivia([], @common.Trivia::empty()), []))
  } else {
    // Generate first key-value pair with state
    gen_safe_key().bind(fn(key) {
      let key_node = @yaml.YamlNode::string_with_trivia(
        key,
        @yaml.YamlScalarStyle::plain(),
        @common.Trivia::empty()
      )

      gen_yaml_node_with_anchors_internal(depth).bind(fn(value_result) {
        let (value, first_anchors) = value_result

        gen_yaml_mapping_elements_with_state(len - 1, depth, first_anchors).fmap(fn(rest_result) {
          let (rest_pairs, all_anchors) = rest_result
          let first_kv = @yaml.YKeyValue::new(
            key_node,
            @common.Trivia::empty(),
            value
          )
          let all_pairs = [first_kv] + rest_pairs
          (@yaml.YamlNode::mapping_with_trivia(all_pairs, @common.Trivia::empty()), all_anchors)
        })
      })
    })
  }
}

///|
/// Generate remaining mapping pairs with accumulated anchor state
fn gen_yaml_mapping_elements_with_state(count : Int, depth : Int, anchors : Array[String]) -> @qc.Gen[(Array[@yaml.YKeyValue], Array[String])] {
  if count == 0 {
    @qc.pure(([], anchors))
  } else {
    @qc.frequency([
      // Regular value (may define new anchors)
      (3, gen_safe_key().bind(fn(key) {
        let key_node = @yaml.YamlNode::string_with_trivia(
          key,
          @yaml.YamlScalarStyle::plain(),
          @common.Trivia::empty()
        )

        gen_yaml_node_with_anchors_internal(depth).bind(fn(value_result) {
          let (value, new_anchors) = value_result
          let combined_anchors = array_concat(anchors, new_anchors)
          gen_yaml_mapping_elements_with_state(count - 1, depth, combined_anchors).fmap(fn(rest) {
            let (rest_pairs, final_anchors) = rest
            let kv = @yaml.YKeyValue::new(key_node, @common.Trivia::empty(), value)
            ([kv] + rest_pairs, final_anchors)
          })
        })
      })),

      // Aliased value (if anchors available)
      (1, if anchors.is_empty() {
        // No anchors yet, generate regular value
        gen_safe_key().bind(fn(key) {
          let key_node = @yaml.YamlNode::string_with_trivia(
            key,
            @yaml.YamlScalarStyle::plain(),
            @common.Trivia::empty()
          )

          gen_yaml_node_with_anchors_internal(depth).bind(fn(value_result) {
            let (value, new_anchors) = value_result
            let combined_anchors = array_concat(anchors, new_anchors)
            gen_yaml_mapping_elements_with_state(count - 1, depth, combined_anchors).fmap(fn(rest) {
              let (rest_pairs, final_anchors) = rest
              let kv = @yaml.YKeyValue::new(key_node, @common.Trivia::empty(), value)
              ([kv] + rest_pairs, final_anchors)
            })
          })
        })
      } else {
        gen_safe_key().bind(fn(key) {
          let key_node = @yaml.YamlNode::string_with_trivia(
            key,
            @yaml.YamlScalarStyle::plain(),
            @common.Trivia::empty()
          )

          gen_yaml_alias(anchors).bind(fn(alias_value) {
            gen_yaml_mapping_elements_with_state(count - 1, depth, anchors).fmap(fn(rest) {
              let (rest_pairs, final_anchors) = rest
              let kv = @yaml.YKeyValue::new(key_node, @common.Trivia::empty(), alias_value)
              ([kv] + rest_pairs, final_anchors)
            })
          })
        })
      }),
    ])
  }
}

///|
/// Extract all anchor names defined in the tree
fn extract_anchor_names(node : @yaml.YamlNode) -> Array[String] {
  match node {
    @yaml.YAnchor(name, _) => [name]
    @yaml.YSequence(elements, _, _) => {
      let mut names = []
      for e in elements {
        names = array_concat(names, extract_anchor_names(e))
      }
      names
    }
    @yaml.YMapping(pairs, _, _) => {
      let mut names = []
      for p in pairs {
        names = array_concat(names, extract_anchor_names(p.key))
        names = array_concat(names, extract_anchor_names(p.value))
      }
      names
    }
    _ => []
  }
}

///|
/// Validate that all YAlias nodes reference existing YAnchor nodes
fn validate_anchor_references(node : @yaml.YamlNode) -> Bool {
  let anchors = extract_anchor_names(node)
  validate_anchors_in_node(node, anchors)
}

///|
/// Validate that all aliases reference existing anchors in a subtree
fn validate_anchors_in_node(node : @yaml.YamlNode, anchors : Array[String]) -> Bool {
  match node {
    @yaml.YAlias(name, _) => array_contains(anchors, name)
    @yaml.YAnchor(_, inner) => validate_anchors_in_node(inner, anchors)
    @yaml.YSequence(elements, _, _) => {
      for e in elements {
        if not(validate_anchors_in_node(e, anchors)) {
          return false
        }
      }
      true
    }
    @yaml.YMapping(pairs, _, _) => {
      for p in pairs {
        if not(validate_anchors_in_node(p.key, anchors)) || not(validate_anchors_in_node(p.value, anchors)) {
          return false
        }
      }
      true
    }
    _ => true
  }
}

///|
/// Helper: check if array contains a string
fn array_contains(arr : Array[String], target : String) -> Bool {
  for elem in arr {
    if elem == target {
      return true
    }
  }
  false
}

///|
/// Helper: concatenate two arrays
fn[T] array_concat(a : Array[T], b : Array[T]) -> Array[T] {
  a + b
}

///|
/// PBT: YAML with anchors/aliases round-trips correctly
test "pbt_yaml_anchor_alias_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_yaml_node_with_anchor_alias(), fn(node) {
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(parsed) => {
          // Compare structure, ignoring trivia
          strip_yaml_trivia(node) == strip_yaml_trivia(parsed)
        }
        Err(_) => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: All aliases in generated YAML reference valid anchors
test "pbt_yaml_aliases_are_valid" {
  @qc.quick_check(
    @qc.forall(gen_yaml_node_with_anchor_alias(), fn(node) {
      validate_anchor_references(node)
    }),
    max_success=100,
  )
}

// ============================================================================
// Phase 2: Complete Scalar Style Generators
// ============================================================================

///|
/// Generate a plain YAML string (unquoted)
fn gen_yaml_plain_string() -> @qc.Gen[@yaml.YamlNode] {
  @qc.frequency([
    // Safe alphanumeric strings
    (5, gen_safe_key().fmap(fn(s) {
      @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::plain(), @common.Trivia::empty())
    })),

    // Strings that look like keywords (will be handled by printer)
    (1, gen_yaml_keyword_like_string().fmap(fn(s) {
      @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::plain(), @common.Trivia::empty())
    })),

    // Empty string
    (1, @qc.pure(@yaml.YamlNode::string_with_trivia("", @yaml.YamlScalarStyle::plain(), @common.Trivia::empty()))),

    // Strings with hyphens, dots (common in keys)
    (2, gen_safe_string().fmap(fn(s) {
      let safe = if s.is_empty() { "key" } else { s }
      @yaml.YamlNode::string_with_trivia(safe, @yaml.YamlScalarStyle::plain(), @common.Trivia::empty())
    })),
  ])
}

///|
/// Generate a single-quoted YAML string
fn gen_yaml_single_quoted_string() -> @qc.Gen[@yaml.YamlNode] {
  @qc.frequency([
    // Regular strings
    (5, gen_safe_string().fmap(fn(s) {
      @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::single_quoted(), @common.Trivia::empty())
    })),

    // Strings with single quotes (will be escaped as '')
    (2, @qc.one_of([
      @qc.pure("it's"),
      @qc.pure("don't"),
      @qc.pure("can't"),
      @qc.pure("John's"),
    ]).fmap(fn(s) {
      @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::single_quoted(), @common.Trivia::empty())
    })),

    // Unicode strings
    (2, gen_unicode_string().fmap(fn(s) {
      @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::single_quoted(), @common.Trivia::empty())
    })),

    // Empty string
    (1, @qc.pure(@yaml.YamlNode::string_with_trivia("", @yaml.YamlScalarStyle::single_quoted(), @common.Trivia::empty()))),
  ])
}

///|
/// Generate a double-quoted YAML string
fn gen_yaml_double_quoted_string() -> @qc.Gen[@yaml.YamlNode] {
  @qc.frequency([
    // Regular strings
    (4, gen_safe_string().fmap(fn(s) {
      @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::double_quoted(), @common.Trivia::empty())
    })),

    // Strings with escape sequences
    (2, gen_escape_needed_string().fmap(fn(s) {
      @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::double_quoted(), @common.Trivia::empty())
    })),

    // Unicode strings
    (2, gen_unicode_string().fmap(fn(s) {
      @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::double_quoted(), @common.Trivia::empty())
    })),

    // Empty string
    (1, @qc.pure(@yaml.YamlNode::string_with_trivia("", @yaml.YamlScalarStyle::double_quoted(), @common.Trivia::empty()))),

    // Strings with special YAML characters
    (1, @qc.one_of([
      @qc.pure("key: value"),
      @qc.pure("[list]"),
      @qc.pure("{mapping}"),
      @qc.pure("comment # text"),
    ]).fmap(fn(s) {
      @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::double_quoted(), @common.Trivia::empty())
    })),
  ])
}

///|
/// Generate a literal block scalar (| style)
fn gen_yaml_literal_block() -> @qc.Gen[@yaml.YamlNode] {
  @qc.sized(fn(size) {
    let num_lines = (size / 10).clamp(min=1, max=5)

    @qc.frequency([
      // Single line
      (3, gen_safe_string().fmap(fn(s) {
        let content = if s.is_empty() { "text" } else { s }
        @yaml.YamlNode::string_with_trivia(content, @yaml.YamlScalarStyle::literal(), @common.Trivia::empty())
      })),

      // Multi-line string (simulated with newlines)
      (2, gen_multi_line_content(num_lines).fmap(fn(content) {
        @yaml.YamlNode::string_with_trivia(content, @yaml.YamlScalarStyle::literal(), @common.Trivia::empty())
      })),

      // Preserved whitespace examples
      (1, @qc.one_of([
        @qc.pure("  indented\n  also indented"),
        @qc.pure("line1\n\nline3"),
        @qc.pure("  "),
      ]).fmap(fn(s) {
        @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::literal(), @common.Trivia::empty())
      })),
    ])
  })
}

///|
/// Helper: generate multi-line content
fn gen_multi_line_content(num_lines : Int) -> @qc.Gen[String] {
  if num_lines <= 1 {
    gen_safe_string().fmap(fn(s) {
      if s.is_empty() { "line1" } else { s }
    })
  } else {
    gen_safe_string().bind(fn(first) {
      gen_multi_line_content(num_lines - 1).fmap(fn(rest) {
        let safe_first = if first.is_empty() { "line" } else { first }
        safe_first + "\n" + rest
      })
    })
  }
}

///|
/// Generate a folded block scalar (> style)
fn gen_yaml_folded_block() -> @qc.Gen[@yaml.YamlNode] {
  @qc.sized(fn(size) {
    let num_lines = (size / 10).clamp(min=1, max=5)

    @qc.frequency([
      // Single line
      (3, gen_safe_string().fmap(fn(s) {
        let content = if s.is_empty() { "text" } else { s }
        @yaml.YamlNode::string_with_trivia(content, @yaml.YamlScalarStyle::folded(), @common.Trivia::empty())
      })),

      // Multi-line string (newlines become spaces in folded)
      (2, gen_multi_line_content(num_lines).fmap(fn(content) {
        @yaml.YamlNode::string_with_trivia(content, @yaml.YamlScalarStyle::folded(), @common.Trivia::empty())
      })),

      // Text that should be folded
      (1, @qc.one_of([
        @qc.pure("wrapped\ntext\nbecomes single line"),
        @qc.pure("paragraph one\n\nparagraph two"),
      ]).fmap(fn(s) {
        @yaml.YamlNode::string_with_trivia(s, @yaml.YamlScalarStyle::folded(), @common.Trivia::empty())
      })),
    ])
  })
}

///|
/// Generate a YAML string with any style (weighted distribution)
fn gen_yaml_scalar_with_any_style() -> @qc.Gen[@yaml.YamlNode] {
  @qc.frequency([
    // Plain style (most common)
    (4, gen_yaml_plain_string()),

    // Double-quoted (common for special characters)
    (3, gen_yaml_double_quoted_string()),

    // Single-quoted
    (2, gen_yaml_single_quoted_string()),

    // Literal block
    (1, gen_yaml_literal_block()),

    // Folded block
    (1, gen_yaml_folded_block()),

    // Non-string scalars
    (2, @qc.one_of([
      @qc.pure(@yaml.YamlNode::null_with_trivia(@common.Trivia::empty())),
      { let g : @qc.Gen[Bool] = @qc.Gen::spawn(); g.fmap(fn(b) { @yaml.YamlNode::bool_with_trivia(b, @common.Trivia::empty()) }) },
      gen_valid_number().fmap(fn(n) { @yaml.YamlNode::number_with_trivia(n, @common.Trivia::empty()) }),
    ])),
  ])
}

///|
/// PBT: All scalar styles round-trip correctly
test "pbt_yaml_all_scalar_styles_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_yaml_scalar_with_any_style(), fn(node) {
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(parsed) => {
          // For scalar styles, compare the actual string content for strings
          match (node, parsed) {
            (@yaml.YString(orig_s, _, _), @yaml.YString(parsed_s, _, _)) => {
              orig_s == parsed_s
            }
            _ => strip_yaml_trivia(node) == strip_yaml_trivia(parsed)
          }
        }
        Err(_) => false
      }
    }),
    max_success=200,
  )
}

///|
/// PBT: Plain scalars preserve content appropriately
test "pbt_yaml_plain_scalar_content_preserved" {
  @qc.quick_check(
    @qc.forall(gen_yaml_plain_string(), fn(node) {
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(@yaml.YString(parsed_s, _, _)) => {
          match node {
            @yaml.YString(orig_s, _, _) => orig_s == parsed_s
            _ => false
          }
        }
        _ => false
      }
    }),
    max_success=100,
  )
}

///|
/// PBT: Literal block scalars preserve formatting
test "pbt_yaml_literal_block_preserves_formatting" {
  @qc.quick_check(
    @qc.forall(gen_yaml_literal_block(), fn(node) {
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(parsed) => strip_yaml_trivia(node) == strip_yaml_trivia(parsed)
        Err(_) => false
      }
    }),
    max_success=50,
  )
}

///|
/// PBT: Folded block scalars preserve formatting
test "pbt_yaml_folded_block_preserves_formatting" {
  @qc.quick_check(
    @qc.forall(gen_yaml_folded_block(), fn(node) {
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(parsed) => strip_yaml_trivia(node) == strip_yaml_trivia(parsed)
        Err(_) => false
      }
    }),
    max_success=50,
  )
}

// ============================================================================
// Phase 3.5: Flow vs Block Collection Style Generators
// ============================================================================

///|
/// Generate a YAML sequence with Flow style ([a, b, c])
fn gen_yaml_flow_sequence(inner_gen : @qc.Gen[@yaml.YamlNode]) -> @qc.Gen[@yaml.YamlNode] {
  let flow_style = @yaml.YamlCollectionStyle::flow()
  // Generate 1-3 elements with Flow style
  @qc.one_of(
    [
      // Single element
      inner_gen.fmap(fn(e) {
        @yaml.YamlNode::sequence_with_style([e], flow_style, @common.Trivia::empty())
      }),
      // Two elements
      inner_gen.bind(fn(e1) {
        inner_gen.fmap(fn(e2) {
          @yaml.YamlNode::sequence_with_style([e1, e2], flow_style, @common.Trivia::empty())
        })
      }),
      // Three elements
      inner_gen.bind(fn(e1) {
        inner_gen.bind(fn(e2) {
          inner_gen.fmap(fn(e3) {
            @yaml.YamlNode::sequence_with_style([e1, e2, e3], flow_style, @common.Trivia::empty())
          })
        })
      }),
    ],
  )
}

///|
/// Generate a YAML mapping with Flow style ({key: value})
fn gen_yaml_flow_mapping(
  key_gen : @qc.Gen[@yaml.YamlNode],
  value_gen : @qc.Gen[@yaml.YamlNode],
) -> @qc.Gen[@yaml.YamlNode] {
  let flow_style = @yaml.YamlCollectionStyle::flow()
  key_gen.bind(fn(key) {
    value_gen.fmap(fn(value) {
      let pair = @yaml.YKeyValue::new(key, @common.Trivia::empty(), value)
      @yaml.YamlNode::mapping_with_style([pair], flow_style, @common.Trivia::empty())
    })
  })
}

///|
/// Generate a YAML node with full style support (scalar styles + collection styles)
fn gen_yaml_node_with_full_style(max_depth : Int) -> @qc.Gen[@yaml.YamlNode] {
  let empty = @common.Trivia::empty()
  if max_depth <= 0 {
    @qc.frequency([
      (5, gen_yaml_scalar_with_any_style()),
      (1, gen_yaml_scalar_with_trivia()),
    ])
  } else {
    let inner = gen_yaml_node_with_full_style(max_depth - 1)
    @qc.frequency([
      (6, gen_yaml_scalar_with_any_style()),
      (3, inner.fmap(fn(e) { @yaml.YamlNode::sequence_with_trivia([e], empty) })),
      (3, inner.bind(fn(k) { inner.fmap(fn(v) {
        let pair = @yaml.YKeyValue::new(k, @common.Trivia::empty(), v)
        @yaml.YamlNode::mapping_with_trivia([pair], empty)
      }) })),
      (1, gen_yaml_anchor(inner)),
    ])
  }
}

///|
/// PBT: Flow-style sequences start with [
test "pbt_yaml_flow_sequence_format" {
  let scalar_gen = gen_yaml_scalar_with_any_style()
  let flow_seq_gen = gen_yaml_flow_sequence(scalar_gen)
  @qc.quick_check(
    @qc.forall(flow_seq_gen, fn(node) {
      let printed = @yaml.print(node)
      // Flow sequences should start with [
      printed.has_prefix("[")
    }),
    max_success=50,
  )
}

///|
/// PBT: Flow-style mappings start with {
test "pbt_yaml_flow_mapping_format" {
  let scalar_gen = gen_yaml_scalar_with_any_style()
  let flow_map_gen = gen_yaml_flow_mapping(scalar_gen, scalar_gen)
  @qc.quick_check(
    @qc.forall(flow_map_gen, fn(node) {
      let printed = @yaml.print(node)
      // Flow mappings should start with {
      printed.has_prefix("{")
    }),
    max_success=50,
  )
}

///|
/// PBT: Flow-style sequences roundtrip correctly
test "pbt_yaml_flow_sequence_roundtrip" {
  let scalar_gen = gen_yaml_scalar_with_any_style()
  let flow_seq_gen = gen_yaml_flow_sequence(scalar_gen)
  @qc.quick_check(
    @qc.forall(flow_seq_gen, fn(node) {
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(parsed) => {
          match parsed {
            @yaml.YSequence(_, @yaml.YamlCollectionStyle::Flow, _) => true
            _ => false  // Parser didn't preserve Flow style
          }
        }
        Err(_) => false
      }
    }),
    max_success=50,
  )
}

///|
/// PBT: Flow-style mappings roundtrip correctly
test "pbt_yaml_flow_mapping_roundtrip" {
  let scalar_gen = gen_yaml_scalar_with_any_style()
  let flow_map_gen = gen_yaml_flow_mapping(scalar_gen, scalar_gen)
  @qc.quick_check(
    @qc.forall(flow_map_gen, fn(node) {
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(parsed) => {
          match parsed {
            @yaml.YMapping(_, @yaml.YamlCollectionStyle::Flow, _) => true
            _ => false  // Parser didn't preserve Flow style
          }
        }
        Err(_) => false
      }
    }),
    max_success=50,
  )
}

///|
/// PBT: Full-style YAML nodes roundtrip correctly
test "pbt_yaml_full_style_roundtrip" {
  @qc.quick_check(
    @qc.forall(gen_yaml_node_with_full_style(4), fn(node) {
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(parsed) => strip_yaml_trivia(node) == strip_yaml_trivia(parsed)
        Err(_) => false
      }
    }),
    max_success=100,
  )
}
