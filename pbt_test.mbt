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
