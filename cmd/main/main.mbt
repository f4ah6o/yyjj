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
  println("  yyjj to-yaml <input>       Convert JSONC string to YAML")
  println("  yyjj to-yaml -f <file>     Convert JSONC file to YAML")
  println("  yyjj to-jsonc <input>      Convert YAML string to JSONC")
  println("  yyjj to-jsonc -f <file>    Convert YAML file to JSONC")
  println("  yyjj help                  Show this help")
  println("")
  println("Examples:")
  println("  yyjj to-yaml '{\"name\": \"test\"}'")
  println("  yyjj to-yaml -f config.jsonc")
  println("  yyjj to-jsonc 'name: test'")
  println("  yyjj to-jsonc -f workflow.yaml")
}

///|
fn read_input(args : Array[String]) -> String? {
  if args.length() < 3 {
    return None
  }
  if args[2] == "-f" || args[2] == "--file" {
    if args.length() < 4 {
      println("Error: missing file path")
      return None
    }
    let path = args[3]
    try {
      let content = @fs.read_file_to_string(path)
      Some(content)
    } catch {
      e => {
        println("Error reading file: " + e.to_string())
        None
      }
    }
  } else {
    Some(args[2])
  }
}

///|
fn run_to_yaml(args : Array[String]) -> Unit {
  match read_input(args) {
    None => {
      println("Usage: yyjj to-yaml <input> | -f <file>")
      return
    }
    Some(input) => {
      match @lib.jsonc_to_yaml(input) {
        Ok(yaml) => println(yaml)
        Err(e) => println("Error: " + e.to_string())
      }
    }
  }
}

///|
fn run_to_jsonc(args : Array[String]) -> Unit {
  match read_input(args) {
    None => {
      println("Usage: yyjj to-jsonc <input> | -f <file>")
      return
    }
    Some(input) => {
      match @lib.yaml_to_jsonc(input) {
        Ok(jsonc) => println(jsonc)
        Err(e) => println("Error: " + e.to_string())
      }
    }
  }
}
