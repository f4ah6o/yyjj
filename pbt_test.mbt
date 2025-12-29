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
    @yaml.YSequence(elements, _) => {
      let stripped = elements.map(strip_yaml_trivia)
      @yaml.YamlNode::sequence_with_trivia(stripped, empty)
    }
    @yaml.YMapping(pairs, _) => {
      let stripped = pairs.map(fn(kv) {
        @yaml.YKeyValue::new(
          strip_yaml_trivia(kv.key),
          empty,
          strip_yaml_trivia(kv.value),
        )
      })
      @yaml.YamlNode::mapping_with_trivia(stripped, empty)
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
    @yaml.YSequence(elements, _) => {
      for e in elements {
        collect_yaml_comments(e, acc)
      }
    }
    @yaml.YMapping(pairs, _) => {
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
