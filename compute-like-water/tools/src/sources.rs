use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::Path;

#[derive(Debug, Clone, Deserialize)]
pub struct Source {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub title: String,
    pub author: String,
    pub publisher: String,
    pub date_published: Option<String>,
    pub url: String,
    pub image_url: Option<String>,
    pub alt_text: String,
    pub license: Option<String>,
    pub accessed: String,
    pub notes: Option<String>,
}

/// Load every `*.json` in the sources directory, keyed and ordered by id.
pub fn load_all(dir: &Path) -> Result<BTreeMap<String, Source>, String> {
    let mut out = BTreeMap::new();
    let entries = std::fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    for entry in entries {
        let path = entry.map_err(|e| e.to_string())?.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let text = std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        let src: Source =
            serde_json::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))?;
        let stem = path.file_stem().unwrap().to_string_lossy();
        if stem != src.id {
            return Err(format!("{}: filename does not match id '{}'", path.display(), src.id));
        }
        out.insert(src.id.clone(), src);
    }
    Ok(out)
}

pub fn escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}
