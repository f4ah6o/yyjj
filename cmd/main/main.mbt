///|
fn main {
  // Simple example: convert JSONC to YAML
  let jsonc = "{\"name\": \"yyjj\", \"version\": \"0.1.0\"}"
  let result = @lib.jsonc_to_yaml(jsonc)
  match result {
    Ok(yaml) => println(yaml)
    Err(_) => println("Error converting JSONC to YAML")
  }
}
