use base64::{engine::general_purpose::STANDARD, Engine};
use qrcode::render::svg;
use qrcode::{EcLevel, QrCode};

/// Render `url` as a QR code and return it as a base64-encoded SVG data URI,
/// suitable for an <img src="..."> attribute.
pub fn data_uri(url: &str) -> Result<String, String> {
    let code = QrCode::with_error_correction_level(url.as_bytes(), EcLevel::M)
        .map_err(|e| format!("qr encode {url}: {e}"))?;
    let svg_xml = code
        .render::<svg::Color>()
        .min_dimensions(120, 120)
        .quiet_zone(true)
        .dark_color(svg::Color("#241f17"))
        .light_color(svg::Color("#ffffff"))
        .build();
    Ok(format!("data:image/svg+xml;base64,{}", STANDARD.encode(svg_xml.as_bytes())))
}
