///|
/// Property-based tests for JSONC/YAML parsing and transformation

///|
/// Strip trivia from JsonNode for structural comparison
fn strip_jsonc_trivia(node : @jsonc.JsonNode) -> @jsonc.JsonNode {
  let empty = @common.Trivia::empty()
  match node {
    @jsonc.JNull(_) => @jsonc.JNull(empty)
    @jsonc.JBool(v, _) => @jsonc.JBool(v, empty)
    @jsonc.JNumber(v, _) => @jsonc.JNumber(v, empty)
    @jsonc.JString(v, _) => @jsonc.JString(v, empty)
    @jsonc.JArray(elements, _) => {
      let stripped = elements.map(strip_jsonc_trivia)
      @jsonc.JArray(stripped, empty)
    }
    @jsonc.JObject(props, _) => {
      let stripped = props.map(fn(p) {
        @jsonc.JProperty::new(p.key, empty, strip_jsonc_trivia(p.value))
      })
      @jsonc.JObject(stripped, empty)
    }
  }
}

///|
/// Strip trivia from YamlNode for structural comparison
fn strip_yaml_trivia(node : @yaml.YamlNode) -> @yaml.YamlNode {
  let empty = @common.Trivia::empty()
  match node {
    @yaml.YNull(_) => @yaml.YNull(empty)
    @yaml.YBool(v, _) => @yaml.YBool(v, empty)
    @yaml.YNumber(v, _) => @yaml.YNumber(v, empty)
    @yaml.YString(v, style, _) => @yaml.YString(v, style, empty)
    @yaml.YSequence(elements, _) => {
      let stripped = elements.map(strip_yaml_trivia)
      @yaml.YSequence(stripped, empty)
    }
    @yaml.YMapping(pairs, _) => {
      let stripped = pairs.map(fn(kv) {
        @yaml.YKeyValue::new(
          strip_yaml_trivia(kv.key),
          empty,
          strip_yaml_trivia(kv.value),
        )
      })
      @yaml.YMapping(stripped, empty)
    }
    @yaml.YAlias(name, _) => @yaml.YAlias(name, empty)
    @yaml.YAnchor(name, inner) => @yaml.YAnchor(name, strip_yaml_trivia(inner))
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
      @qc.Arbitrary::arbitrary().map(fn(n : Int) { n.to_string() }),
    ],
  )
}

///|
/// Generate a safe string (no control chars that would break parsing)
fn gen_safe_string() -> @qc.Gen[String] {
  @qc.Arbitrary::arbitrary().map(fn(s : String) {
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
/// Generate a simple scalar JsonNode (no recursion)
fn gen_json_scalar() -> @qc.Gen[@jsonc.JsonNode] {
  let empty = @common.Trivia::empty()
  @qc.one_of(
    [
      @qc.pure(@jsonc.JNull(empty)),
      @qc.Arbitrary::arbitrary().map(fn(b : Bool) { @jsonc.JBool(b, empty) }),
      gen_valid_number().map(fn(n) { @jsonc.JNumber(n, empty) }),
      gen_safe_string().map(fn(s) { @jsonc.JString(s, empty) }),
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
      (4, @qc.pure(@jsonc.JNull(empty))),
      (4, @qc.Arbitrary::arbitrary().map(fn(b : Bool) { @jsonc.JBool(b, empty) })),
      (4, gen_valid_number().map(fn(n) { @jsonc.JNumber(n, empty) })),
      (4, gen_safe_string().map(fn(s) { @jsonc.JString(s, empty) })),
      // Empty array
      (1, @qc.pure(@jsonc.JArray([], empty))),
      // Empty object
      (1, @qc.pure(@jsonc.JObject([], empty))),
      // Small array with scalars
      (
        1,
        gen_json_scalar().bind(fn(elem1) {
          gen_json_scalar().map(fn(elem2) { @jsonc.JArray([elem1, elem2], empty) })
        }),
      ),
      // Small object with scalars
      (
        1,
        gen_safe_string().bind(fn(key1) {
          gen_json_scalar().bind(fn(val1) {
            gen_safe_string().bind(fn(key2) {
              gen_json_scalar().map(fn(val2) {
                @jsonc.JObject(
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
      @qc.pure(@yaml.YNull(empty)),
      @qc.Arbitrary::arbitrary().map(fn(b : Bool) { @yaml.YBool(b, empty) }),
      gen_valid_number().map(fn(n) { @yaml.YNumber(n, empty) }),
      gen_safe_string().map(fn(s) {
        @yaml.YString(s, @yaml.YamlScalarStyle::DoubleQuoted, empty)
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
      (4, @qc.pure(@yaml.YNull(empty))),
      (4, @qc.Arbitrary::arbitrary().map(fn(b : Bool) { @yaml.YBool(b, empty) })),
      (4, gen_valid_number().map(fn(n) { @yaml.YNumber(n, empty) })),
      (
        4,
        gen_safe_string().map(fn(s) {
          @yaml.YString(s, @yaml.YamlScalarStyle::DoubleQuoted, empty)
        }),
      ),
      // Empty sequence
      (1, @qc.pure(@yaml.YSequence([], empty))),
      // Empty mapping
      (1, @qc.pure(@yaml.YMapping([], empty))),
      // Small sequence with scalars
      (
        1,
        gen_yaml_scalar().bind(fn(elem1) {
          gen_yaml_scalar().map(fn(elem2) {
            @yaml.YSequence([elem1, elem2], empty)
          })
        }),
      ),
      // Small mapping with scalars
      (
        1,
        gen_safe_string().bind(fn(key1) {
          gen_yaml_scalar().bind(fn(val1) {
            gen_safe_string().bind(fn(key2) {
              gen_yaml_scalar().map(fn(val2) {
                @yaml.YMapping(
                  [
                    @yaml.YKeyValue::new(
                      @yaml.YString(
                        key1,
                        @yaml.YamlScalarStyle::DoubleQuoted,
                        empty,
                      ),
                      empty,
                      val1,
                    ),
                    @yaml.YKeyValue::new(
                      @yaml.YString(
                        key2,
                        @yaml.YamlScalarStyle::DoubleQuoted,
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
  @qc.quick_check!(
    @qc.forall(gen_simple_json_node(), fn(node) {
      let printed = @jsonc.print(node)
      match @jsonc.parse(printed) {
        Ok(parsed) => strip_jsonc_trivia(node) == strip_jsonc_trivia(parsed)
        Err(_) => false
      }
    })
    |> @qc.with_max_success(100),
  )
}

///|
/// PBT: YAML print -> parse round-trip preserves structure
test "pbt_yaml_roundtrip" {
  @qc.quick_check!(
    @qc.forall(gen_simple_yaml_node(), fn(node) {
      let printed = @yaml.print(node)
      match @yaml.parse(printed) {
        Ok(parsed) => strip_yaml_trivia(node) == strip_yaml_trivia(parsed)
        Err(_) => false
      }
    })
    |> @qc.with_max_success(100),
  )
}

///|
/// PBT: JSONC -> YAML -> JSONC transformation preserves structure
test "pbt_jsonc_yaml_jsonc_transform" {
  @qc.quick_check!(
    @qc.forall(gen_simple_json_node(), fn(node) {
      // JSONC -> YAML
      let yaml_node = @transform.jsonc_to_yaml(node)
      // YAML -> JSONC
      let back = @transform.yaml_to_jsonc(yaml_node)
      // Compare structures (ignoring trivia)
      strip_jsonc_trivia(node) == strip_jsonc_trivia(back)
    })
    |> @qc.with_max_success(100),
  )
}

///|
/// PBT: Full string round-trip JSONC -> YAML -> JSONC
test "pbt_string_roundtrip_jsonc_yaml_jsonc" {
  @qc.quick_check!(
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
    })
    |> @qc.with_max_success(100),
  )
}
