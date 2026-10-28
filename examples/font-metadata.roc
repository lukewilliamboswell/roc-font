app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../package/main.roc",
}

import cli.Stdout
import font.Font

# Original font facts used by a PDF embedding or subsetting consumer.
# The caller keeps embedding policy and table rewriting outside roc-font.
main! = |_args| inspect!(Font.serif)

inspect! : Font => Try({}, _)
inspect! = |face| {
	Stdout.line!("Full name: ${Font.full_name(face) ?? "not supplied"}")?
	Stdout.line!("PostScript name: ${Font.postscript_name(face) ?? "not supplied"}")?
	match Font.embedding_flags(face) {
		Present(flags) => Stdout.line!("Original embedding flags: ${flags.to_str()}")?
		Absent => Stdout.line!("Embedding flags not supplied")?
	}
	header = Font.stored_header_metrics(face)
	Stdout.line!("Stored header: ${header.ascent.to_str()}, ${header.descent.to_str()}, ${header.line_gap.to_str()}")?
	match Font.table_bytes(face, "head") {
		Present(bytes) => Stdout.line!("Original head table: ${bytes.len().to_str()} bytes")?
		Absent => Stdout.line!("No head table")?
	}
	Stdout.line!("Original directory: ${Font.tables(face).len().to_str()} tables")?
	Ok({})
}
