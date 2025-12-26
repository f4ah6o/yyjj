///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    print_usage()
    return
  }
  let command = args[1]
  match command {
    "to-yaml" => run_to_yaml(args)
    "to-jsonc" => run_to_jsonc(args)
    "help" | "--help" | "-h" => print_usage()
    _ => {
      println("Unknown command: " + command)
      print_usage()
    }
  }
}

///|
fn print_usage() -> Unit {
  println("yyjj - JSONC/YAML bidirectional converter")
  println("")
  println("Usage:")
  println("  yyjj to-yaml <input>    Convert JSONC to YAML")
  println("  yyjj to-jsonc <input>   Convert YAML to JSONC")
  println("  yyjj help               Show this help")
  println("")
  println("Examples:")
  println("  yyjj to-yaml '{\"name\": \"test\"}'")
  println("  yyjj to-jsonc 'name: test'")
}

///|
fn run_to_yaml(args : Array[String]) -> Unit {
  if args.length() < 3 {
    println("Error: missing input")
    println("Usage: yyjj to-yaml <input>")
    return
  }
  let input = args[2]
  match @lib.jsonc_to_yaml(input) {
    Ok(yaml) => println(yaml)
    Err(e) => println("Error: " + e.to_string())
  }
}

///|
fn run_to_jsonc(args : Array[String]) -> Unit {
  if args.length() < 3 {
    println("Error: missing input")
    println("Usage: yyjj to-jsonc <input>")
    return
  }
  let input = args[2]
  match @lib.yaml_to_jsonc(input) {
    Ok(jsonc) => println(jsonc)
    Err(e) => println("Error: " + e.to_string())
  }
}
