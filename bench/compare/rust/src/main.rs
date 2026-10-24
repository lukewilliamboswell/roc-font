//! ttf-parser and rustybuzz comparison program for scripts/bench.py.
//!
//! Usage: `compare <library> <iterations>` with one case file on stdin (see
//! bench/roc/FontBench.roc): `<operation>\n<font length>\n<font bytes><text>`.
//! The case is prepared outside the timed region; the operation runs
//! `iterations` times inside it, then one JSON line is printed:
//! {"iterations", "elapsed_ns", "successes", "checksum"}.
//!
//! - `ttf-parser`: `read` (Face::parse, then the tables the Roc reader
//!   checks), `cmap` (glyph_index), `advance` (glyph_hor_advance).
//! - `rustybuzz`: `read` (Face::from_slice) and `shape` (rustybuzz::shape with
//!   the default features).
//!
//! Any other pair exits 3 (unsupported).
use std::io::Read;
use std::time::Instant;

fn decode_utf8(s: &[u8]) -> Vec<u32> {
    // String::from_utf8_lossy replaces each maximal invalid subpart with one
    // U+FFFD, while FontBench replaces each bad byte; benchmark texts are
    // valid UTF-8, so the difference never shows.
    String::from_utf8_lossy(s).chars().map(|c| c as u32).collect()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let library = args.get(1).cloned().unwrap_or_default();
    let iterations: u64 = args.last().and_then(|a| a.parse().ok()).unwrap_or(1);
    let mut input = Vec::new();
    std::io::stdin().read_to_end(&mut input).expect("stdin");
    let nl1 = input.iter().position(|&b| b == b'\n').expect("header");
    let nl2 = nl1 + 1 + input[nl1 + 1..].iter().position(|&b| b == b'\n').expect("header");
    let op = std::str::from_utf8(&input[..nl1]).unwrap().to_string();
    let font_len: usize = std::str::from_utf8(&input[nl1 + 1..nl2]).unwrap().parse().unwrap();
    let data = &input[nl2 + 1..];
    let (font_bytes, text) = data.split_at(font_len);
    let text_str = String::from_utf8_lossy(text).into_owned();
    let cps = decode_utf8(text);

    let face = ttf_parser::Face::parse(font_bytes, 0).expect("font");
    let glyphs: Vec<ttf_parser::GlyphId> = cps
        .iter()
        .map(|&cp| char::from_u32(cp).and_then(|c| face.glyph_index(c)).unwrap_or(ttf_parser::GlyphId(0)))
        .collect();
    let hb_face = rustybuzz::Face::from_slice(font_bytes, 0).expect("font");

    let run: Box<dyn Fn() -> Option<u64>> = match (library.as_str(), op.as_str()) {
        ("ttf-parser", "read") => Box::new(|| {
            let f = ttf_parser::Face::parse(font_bytes, 0).ok()?;
            let t = f.tables();
            // The lookups are kept observable through black_box; the
            // checksum is glyph count plus units per em, as in FontBench.
            std::hint::black_box(f.glyph_index('a').map(|g| f.glyph_hor_advance(g)));
            std::hint::black_box(t.gsub.map(|g| g.lookups.len()));
            std::hint::black_box(t.gpos.map(|g| g.lookups.len()));
            Some(f.number_of_glyphs() as u64 + f.units_per_em() as u64)
        }),
        ("rustybuzz", "read") => Box::new(|| {
            let f = rustybuzz::Face::from_slice(font_bytes, 0)?;
            Some(f.number_of_glyphs() as u64 + f.units_per_em() as u64)
        }),
        ("ttf-parser", "cmap") => Box::new(|| {
            let mut sum = 0u64;
            for &cp in &cps {
                if let Some(g) = char::from_u32(cp).and_then(|c| face.glyph_index(c)) {
                    sum += g.0 as u64 + 1;
                }
            }
            Some(sum)
        }),
        ("ttf-parser", "advance") => Box::new(|| {
            let mut sum = 0u64;
            for &g in &glyphs {
                sum += face.glyph_hor_advance(g).unwrap_or(0) as u64;
            }
            Some(sum)
        }),
        ("rustybuzz", "shape") => Box::new(|| {
            let mut buffer = rustybuzz::UnicodeBuffer::new();
            buffer.push_str(&text_str);
            buffer.set_direction(rustybuzz::Direction::LeftToRight);
            buffer.set_script(rustybuzz::script::LATIN);
            buffer.set_language("en".parse().unwrap());
            let out = rustybuzz::shape(&hb_face, &[], buffer);
            let mut sum = 0u64;
            for (info, pos) in out.glyph_infos().iter().zip(out.glyph_positions()) {
                sum = sum
                    .wrapping_add(info.glyph_id as u64 + info.cluster as u64)
                    .wrapping_add(pos.x_advance as i64 as u64);
            }
            Some(sum)
        }),
        _ => {
            eprintln!("unsupported: {library} {op}");
            std::process::exit(3);
        }
    };

    let mut checksum = 0u64;
    let mut successes = 0u64;
    let start = Instant::now();
    for _ in 0..iterations {
        match std::hint::black_box(run()) {
            Some(sum) => {
                checksum = checksum.wrapping_add(sum);
                successes += 1;
            }
            None => {}
        }
    }
    let elapsed = start.elapsed().as_nanos();
    println!("{{\"iterations\":{iterations},\"elapsed_ns\":{elapsed},\"successes\":{successes},\"checksum\":{checksum}}}");
}
