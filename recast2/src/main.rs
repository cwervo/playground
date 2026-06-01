use clap::{Arg, Command};
use reqwest::blocking::Client;
use std::fs;
use swc_ecma_parser::{Parser, StringInput, Syntax};
use swc_common::{SourceMap, FileName};
use swc_ecma_ast::Module;
use serde_json::json;

fn main() {
    let matches = Command::new("ollama-ast-cli")
        .version("0.1.0")
        .author("cwervo")
        .about("Rust CLI for AST-based code editing with Ollama agent")
        .arg(Arg::new("edit")
            .help("Edit code using AST and Ollama agent")
            .required(true)
            .index(1))
        .get_matches();

    let file = matches.get_one::<String>("edit").unwrap();
    let code = fs::read_to_string(file).expect("Failed to read file");

    // Parse JS code to AST
    let cm = SourceMap::default();
    let fm = cm.new_source_file(FileName::Custom(file.to_string()), code.clone());
    let mut parser = Parser::new(
        Syntax::Es(Default::default()),
        StringInput::from(&*fm),
        None,
    );
    let module: Module = parser.parse_module().expect("Failed to parse module");
    let ast_json = serde_json::to_string(&module).expect("Failed to serialize AST");

    // Send AST to Ollama agent
    let client = Client::new();
    let ollama_url = "http://localhost:11434/api/ast";
    let resp = client.post(ollama_url)
        .json(&json!({"ast": ast_json}))
        .send();

    match resp {
        Ok(r) => {
            println!("Ollama response: {}", r.text().unwrap_or_default());
        }
        Err(e) => {
            eprintln!("Failed to connect to Ollama agent: {}", e);
        }
    }
}
