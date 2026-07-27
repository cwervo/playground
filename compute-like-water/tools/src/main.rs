mod qr;
mod sources;
mod talk;
mod works_cited;

use std::env;
use std::path::Path;

fn main() {
    let args: Vec<String> = env::args().collect();
    let cmd = args.get(1).map(String::as_str).unwrap_or("help");
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf();

    match cmd {
        "cite" => {
            let srcs = sources::load_all(&root.join("sources")).expect("loading sources");
            let html = works_cited::standalone_page(&srcs);
            let out = root.join("Works_Cited.html");
            std::fs::write(&out, html).expect("writing Works_Cited.html");
            println!("wrote {} ({} sources)", out.display(), srcs.len());
        }
        "build" => {
            let srcs = sources::load_all(&root.join("sources")).expect("loading sources");
            let script = std::fs::read_to_string(root.join("talk.md")).expect("reading talk.md");
            let talk = talk::parse(&script).expect("parsing talk.md");
            let html = talk::render_index(&talk, &srcs).expect("rendering index.html");
            let out = root.join("index.html");
            std::fs::write(&out, html).expect("writing index.html");
            println!(
                "wrote {} ({} slides, {} sources, ~{} spoken words)",
                out.display(),
                talk.slides.len(),
                srcs.len(),
                talk.word_count()
            );
        }
        _ => {
            eprintln!("usage: talkgen <cite|build>");
            eprintln!("  cite   generate Works_Cited.html from sources/*.json");
            eprintln!("  build  generate index.html from talk.md + sources/*.json");
            std::process::exit(2);
        }
    }
}
