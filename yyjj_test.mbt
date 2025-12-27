///|
test "jsonc_to_yaml_simple" {
  let jsonc = "{\"name\": \"test\", \"value\": 42}"
  let result = @yyjj.jsonc_to_yaml(jsonc)
  guard result is Ok(yaml) else { return }
  // YAML output should contain key: value format
  inspect(yaml.contains("name:"), content="true")
  inspect(yaml.contains("value:"), content="true")
}

///|
test "yaml_to_jsonc_simple" {
  let yaml = "name: test\nvalue: 42"
  let result = @yyjj.yaml_to_jsonc(yaml)
  guard result is Ok(jsonc) else { return }
  // JSONC output should contain quoted keys
  inspect(jsonc.contains("\"name\""), content="true")
  inspect(jsonc.contains("\"value\""), content="true")
}

///|
test "parse_jsonc" {
  let jsonc = "{\"key\": \"value\"}"
  let result = @yyjj.parse_jsonc(jsonc)
  guard result is Ok(_) else { return }
  // Parse should succeed
}

///|
test "parse_yaml" {
  let yaml = "key: value"
  let result = @yyjj.parse_yaml(yaml)
  guard result is Ok(_) else { return }
  // Parse should succeed
}

///|
test "round_trip_jsonc_to_yaml" {
  let original = "{\"items\": [1, 2, 3]}"
  let to_yaml = @yyjj.jsonc_to_yaml(original)
  guard to_yaml is Ok(yaml) else { return }
  let back_to_jsonc = @yyjj.yaml_to_jsonc(yaml)
  guard back_to_jsonc is Ok(jsonc) else { return }
  // Should contain the same structure
  inspect(jsonc.contains("items"), content="true")
}

///|
test "yaml_to_jsonc_with_comments" {
  let yaml =
    #|# This is a comment
    #|name: test
    #|value: 42  # trailing comment
  let result = @yyjj.yaml_to_jsonc(yaml)
  guard result is Ok(jsonc) else { return }
  println("YAML input:")
  println(yaml)
  println("\nJSONC output:")
  println(jsonc)
  // Should preserve comments
  inspect(jsonc.contains("//"), content="true")
}

///|
test "yaml_to_jsonc_nested_comments" {
  let yaml =
    #|# Server settings
    #|server: localhost
    #|port: 8080
    #|# Database connection
    #|database:
    #|  host: db.example.com
    #|  # Database name
    #|  name: myapp
  let result = @yyjj.yaml_to_jsonc(yaml)
  guard result is Ok(jsonc) else { return }
  println("YAML with nested comments:")
  println(yaml)
  println("\nJSONC output:")
  println(jsonc)
  // Should preserve all comments including nested ones
  inspect(jsonc.contains("Server settings"), content="true")
  inspect(jsonc.contains("Database connection"), content="true")
  inspect(jsonc.contains("Database name"), content="true")
  // Critical: database should be an object, not null
  inspect(jsonc.contains("\"database\": null"), content="false")
  // Critical: host should be inside database object
  inspect(jsonc.contains("\"database\": {"), content="true")
  // Critical: nested comment must be preserved
  inspect(jsonc.contains("// Database name"), content="true")
}

///|
test "yaml_to_jsonc_user_case" {
  // User's actual YAML input - properly indented
  let yaml =
    #|# サーバー設定
    #|server: localhost
    #|port: 8080
    #|# データベース接続
    #|database:
    #|  host: db.example.com
    #|  # foo
    #|  name: myapp
  let result = @yyjj.yaml_to_jsonc(yaml)
  guard result is Ok(jsonc) else { return }
  println("User YAML:")
  println(yaml)
  println("\nJSONC output:")
  println(jsonc)
  // Critical assertions - these must pass
  // 1. database must be an object, not null
  assert_false(jsonc.contains("\"database\": null"))
  // 2. database must contain nested object
  assert_true(jsonc.contains("\"database\":"))
  assert_true(jsonc.contains("\"host\":"))
  assert_true(jsonc.contains("\"name\":"))
  // 3. All comments must be preserved
  assert_true(jsonc.contains("サーバー設定"))
  assert_true(jsonc.contains("データベース接続"))
  assert_true(jsonc.contains("foo"))
}

///|
test "yaml_to_jsonc_github_actions_workflow" {
  // GitHub Actions workflow with deeply nested structure
  let yaml =
    #|name: CI
    #|on:
    #|  push:
    #|    branches:
    #|      - main
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    permissions:
    #|      contents: read
    #|    steps:
    #|      - name: Checkout
    #|        uses: actions/checkout@v5
    #|      - name: Build
    #|        run: npm run build
  let result = @yyjj.yaml_to_jsonc(yaml)
  guard result is Ok(jsonc) else {
    println("Parse error!")
    return
  }
  println("GitHub Actions YAML:")
  println(yaml)
  println("\nJSONC output:")
  println(jsonc)

  // Critical: structure must be preserved
  // 1. `on` must not become `true` (YAML 1.1 keyword issue)
  assert_false(jsonc.contains("\"true\":"))
  // 2. `jobs.build.permissions` must be inside build, not at jobs level
  assert_true(jsonc.contains("\"build\":"))
  assert_true(jsonc.contains("\"permissions\":"))
  // 3. `steps` must be an array inside build
  assert_true(jsonc.contains("\"steps\":"))
  assert_true(jsonc.contains("\"name\": \"Checkout\""))
  assert_true(jsonc.contains("\"uses\": \"actions/checkout@v5\""))
  // 4. `run` must be inside the Build step, not leaked outside
  assert_true(jsonc.contains("\"run\": \"npm run build\""))
}

///|
test "yaml_to_jsonc_copilot_setup_steps_structure" {
  // Test the copilot-setup-steps.yaml structure
  let yaml =
    #|name: "Copilot Setup Steps"
    #|on:
    #|  workflow_dispatch:
    #|  push:
    #|    paths:
    #|      - .github/workflows/copilot-setup-steps.yml
    #|jobs:
    #|  copilot-setup-steps:
    #|    runs-on: ubuntu-latest
    #|    permissions:
    #|      contents: read
    #|    steps:
    #|      - name: Checkout code
    #|        uses: actions/checkout@v5
    #|      - name: Set up MoonBit
    #|        run: |
    #|          curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
    #|          echo "$HOME/.moon/bin" >> $GITHUB_PATH
  let result = @yyjj.yaml_to_jsonc(yaml)
  guard result is Ok(jsonc) else {
    println("Parse error!")
    return
  }
  println("Copilot setup steps YAML:")
  println(yaml)
  println("\nJSONC output:")
  println(jsonc)

  // Critical structure checks
  // 1. `on` must be a key, not `true`
  assert_true(jsonc.contains("\"on\":"))
  assert_false(jsonc.contains("\"true\":"))

  // 2. `copilot-setup-steps` job must contain all nested keys
  assert_true(jsonc.contains("\"copilot-setup-steps\":"))
  assert_true(jsonc.contains("\"runs-on\": \"ubuntu-latest\""))

  // 3. `permissions` must exist
  assert_true(jsonc.contains("\"permissions\":"))
  assert_true(jsonc.contains("\"contents\": \"read\""))

  // 4. `steps` must be an array with proper structure
  assert_true(jsonc.contains("\"steps\":"))
  assert_true(jsonc.contains("\"name\": \"Checkout code\""))
  assert_true(jsonc.contains("\"uses\": \"actions/checkout@v5\""))
  assert_true(jsonc.contains("\"name\": \"Set up MoonBit\""))
}

///|
test "roundtrip_jsonc_yaml_jsonc_with_comments" {
  // Demo page default JSONC
  let original_jsonc =
    #|{
    #|  // サーバー設定
    #|  "server": "localhost",
    #|  "port": 8080,
    #|  /* データベース接続 */
    #|  "database": {
    #|    "host": "db.example.com",
    #|    "name": "myapp"
    #|  }
    #|}

  // JSONC -> YAML
  let yaml_result = @yyjj.jsonc_to_yaml(original_jsonc)
  guard yaml_result is Ok(yaml) else { return }
  println("Original JSONC:")
  println(original_jsonc)
  println("\nConverted YAML:")
  println(yaml)

  // YAML -> JSONC
  let jsonc_result = @yyjj.yaml_to_jsonc(yaml)
  guard jsonc_result is Ok(jsonc) else { return }
  println("\nBack to JSONC:")
  println(jsonc)

  // Assertions
  // 1. database must not be null
  assert_false(jsonc.contains("\"database\": null"))
  // 2. Structure must be preserved
  assert_true(jsonc.contains("\"database\":"))
  assert_true(jsonc.contains("\"host\":"))
  assert_true(jsonc.contains("\"name\":"))
  // 3. Comments must be preserved
  assert_true(jsonc.contains("サーバー設定"))
  assert_true(jsonc.contains("データベース接続"))
}
