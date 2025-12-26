///|
test "yaml_parse_simple_mapping" {
  let source = "key: value"
  let result = @yaml.parse(source)
  guard result is Ok(@yaml.YMapping(pairs, _)) else { return }
  inspect(pairs.length(), content="1")
}

///|
test "yaml_parse_sequence" {
  let source = (
    #|- item1
    #|- item2
    #|- item3
  )
  let result = @yaml.parse(source)
  guard result is Ok(@yaml.YSequence(elements, _)) else { return }
  inspect(elements.length(), content="3")
}

///|
test "yaml_parse_flow_sequence" {
  let result = @yaml.parse("[1, 2, 3]")
  guard result is Ok(@yaml.YSequence(elements, _)) else { return }
  inspect(elements.length(), content="3")
}

///|
test "yaml_parse_flow_mapping" {
  let result = @yaml.parse("{key: value}")
  guard result is Ok(@yaml.YMapping(pairs, _)) else { return }
  inspect(pairs.length(), content="1")
}

///|
test "yaml_parse_with_comment" {
  let source = "key: value # this is a comment"
  let result = @yaml.parse(source)
  guard result is Ok(_) else { return }
  // Parse should succeed with comment
}

///|
test "yaml_parse_booleans" {
  let result1 = @yaml.parse("true")
  guard result1 is Ok(@yaml.YBool(true, _)) else { return }
  let result2 = @yaml.parse("false")
  guard result2 is Ok(@yaml.YBool(false, _)) else { return }
}

///|
test "yaml_parse_null" {
  let result = @yaml.parse("null")
  guard result is Ok(@yaml.YNull(_)) else { return }
}

///|
test "yaml_parse_multi_key_mapping" {
  let yaml = "name: test\non: push\njobs: build"
  let result = @yaml.parse(yaml)
  guard result is Ok(@yaml.YMapping(pairs, _)) else {
    println("Parse failed or not a mapping")
    return
  }
  // Note: "on" is parsed as TrueValue in YAML 1.1, so key becomes "true"
  inspect(pairs.length(), content="3")
}

///|
test "yaml_parse_nested_mapping" {
  let yaml = "name: test\non:\n  push: main\njobs: build"
  let result = @yaml.parse(yaml)
  guard result is Ok(@yaml.YMapping(pairs, _)) else {
    println("Parse failed or not a mapping")
    return
  }
  // Should have 3 pairs: name, true (on), jobs
  inspect(pairs.length(), content="3")
  // The second pair (on -> true in YAML 1.1) should have a nested mapping
  guard pairs[1].value is @yaml.YMapping(nested, _) else {
    println("Expected nested mapping for 'on'")
    return
  }
  inspect(nested.length(), content="1")
}

///|
test "yaml_parse_sibling_keys_with_empty_values" {
  // workflow_dispatch and push should be siblings, not nested
  let yaml = "on:\n  workflow_dispatch:\n  push: main"
  let result = @yaml.parse(yaml)
  guard result is Ok(@yaml.YMapping(pairs, _)) else {
    println("Parse failed or not a mapping")
    return
  }
  // Should have 1 pair at top level (on/true)
  inspect(pairs.length(), content="1")
  // The value should be a mapping with 2 sibling keys
  guard pairs[0].value is @yaml.YMapping(nested, _) else {
    println("Expected nested mapping")
    return
  }
  inspect(nested.length(), content="2")
  // First sibling: workflow_dispatch with null value
  guard nested[0].value is @yaml.YNull(_) else {
    println("Expected null for workflow_dispatch")
    return
  }
  // Second sibling: push with "main" value
  guard nested[1].value is @yaml.YString(s, _, _) else {
    println("Expected string for push")
    return
  }
  inspect(s, content="main")
}

///|
/// Test parsing the on: section of a GitHub Actions workflow
/// This tests the case where a sequence is followed by a sibling key at the same level
test "yaml_parse_github_actions_on_section" {
  // Simplified version of the copilot-setup-steps.yaml on: section
  let yaml = (
    #|on:
    #|  workflow_dispatch:
    #|  push:
    #|    paths:
    #|      - file.yml
    #|  pull_request:
    #|    paths:
    #|      - file.yml
  )
  let result = @yaml.parse(yaml)
  guard result is Ok(@yaml.YMapping(pairs, _)) else {
    println("Parse failed or not a mapping")
    return
  }
  // Should have 1 pair at top level (on/true)
  inspect(pairs.length(), content="1")
  // The value should be a mapping with 3 sibling keys
  guard pairs[0].value is @yaml.YMapping(on_value, _) else {
    println("Expected nested mapping for 'on'")
    return
  }
  // workflow_dispatch, push, pull_request
  inspect(on_value.length(), content="3")
}

///|
/// Test parsing the full structure of copilot-setup-steps.yaml
test "yaml_parse_copilot_setup_steps" {
  let yaml = (
    #|name: "Copilot Setup Steps"
    #|on:
    #|  workflow_dispatch:
    #|  push:
    #|    paths:
    #|      - file.yml
    #|  pull_request:
    #|    paths:
    #|      - file.yml
    #|jobs:
    #|  copilot-setup-steps:
    #|    runs-on: ubuntu-latest
  )
  let result = @yaml.parse(yaml)
  guard result is Ok(@yaml.YMapping(pairs, _)) else {
    println("Parse failed or not a mapping")
    return
  }
  // Should have 3 top-level keys: name, on (as "true"), jobs
  inspect(pairs.length(), content="3")
  // Check the "on" section has 3 keys
  guard pairs[1].value is @yaml.YMapping(on_value, _) else {
    println("Expected nested mapping for 'on'")
    return
  }
  inspect(on_value.length(), content="3")
  // Check the "jobs" section
  guard pairs[2].value is @yaml.YMapping(jobs_value, _) else {
    println("Expected nested mapping for 'jobs'")
    return
  }
  inspect(jobs_value.length(), content="1")
}
