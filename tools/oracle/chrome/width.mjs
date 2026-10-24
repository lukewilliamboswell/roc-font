// Chrome width oracle for roc-font. Authoring only; never part of the Roc
// package. scripts/record_oracle.py runs it for cases of kind `width`.
//
//   node tools/oracle/chrome/width.mjs versions        one JSON object: extractor, puppeteer, chrome
//   node tools/oracle/chrome/width.mjs run < req.jsonl one JSON response per request line, in order
//
// A request is `{"kind": "width", "font": <path>, "options": [...],
// "unicodes": [...]}`; a response is `{"status": "ok"|"unsupported"|"error",
// "result": "width:<n>" or null, "backend": <str>, "detail": <object>}`, the
// same shape tools/oracle/extract.py answers.
//
// What it measures: the advance width of the text in the pinned Chrome with
// the browser's default features (`font-kerning: auto`, `liga`, `calt` and
// the rest of HarfBuzz's defaults, as Chrome applies them), in font units.
// The font is loaded from its bytes with the FontFace API, so Chrome's own
// font sanitiser (OTS) decides whether it loads; a font it refuses is an
// `error` with the reason in `detail`.
//
// Precision. The text is laid out in an absolutely positioned
// `white-space: pre` span whose font size is the font's units per em in CSS
// pixels, so one pixel is one font unit and no scaling happens between the
// font and the result. Chrome shapes with HarfBuzz at 16.16 fixed point
// (`SkScalarToHBFixed`), so each glyph's advance is exact to 1/65536 of a
// unit, and layout stores the inline width in Blink layout units of 1/64 px,
// so the span's width is within 1/64 of a font unit of the shaped width.
// `--font-render-hinting=none` keeps hinting from rounding advances to whole
// pixels. The width is recorded as an integer when it is within 1/64 of one
// (it always is for a static font with integer advances and kerning),
// otherwise as a decimal with six places (exact for multiples of 1/64).
//
// The span, not canvas `measureText`, is the reference: it is the layout path
// HTML and SVG text take, and it shapes the run as a whole, as HarfBuzz does.
// Canvas measures word by word (Blink caches shaping per space-separated
// word), so a contextual substitution that looks across a space differs
// there; its width is kept in `detail` as a diagnostic only.
//
// Out of scope, reported as `unsupported`: any option other than `--width`
// (accepted for case files that still spell the kind as an option) and
// `--no-glyph-names`; code points the font's cmap does not map (Chrome would
// draw them with a fallback font, so the width would not be this font's);
// control characters (tabs and line breaks would be laid out, not shaped);
// cmap formats other than 0, 4, 6 and 12; variable fonts (Chrome applies
// automatic optical sizing, so the instance depends on the font size).
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(here, 'package.json'));
const PIN = JSON.parse(fs.readFileSync(path.join(here, 'pin.json'), 'utf8'));
const EXTRACTOR_VERSION = PIN.extractor;
const BACKEND = 'Chrome span layout width (Puppeteer)';
const ALLOWED_OPTIONS = new Set(['--width', '--no-glyph-names']);
// Widths this close to an integer are recorded as that integer (see above).
const INTEGER_TOLERANCE = 1 / 64;

// ------------------------------------------------------------ font facts

class Unsupported extends Error {}

// The facts needed before measuring: units per em, whether the font is
// variable, and which code points its cmap maps. Throws on bytes too broken
// to read; Chrome would refuse those too, and its verdict is what is
// recorded, so callers only use this for fonts Chrome loaded.
function fontFacts(bytes) {
	const b = Buffer.from(bytes);
	const need = (offset, length) => {
		if (offset < 0 || offset + length > b.length) throw new Error('font data ends early');
	};
	const u16 = o => (need(o, 2), b.readUInt16BE(o));
	const u32 = o => (need(o, 4), b.readUInt32BE(o));
	const tables = new Map();
	const count = u16(4);
	for (let i = 0; i < count; i++) {
		const r = 12 + 16 * i;
		need(r, 16);
		tables.set(b.toString('latin1', r, r + 4), { offset: u32(r + 8), length: u32(r + 12) });
	}
	const head = tables.get('head');
	const cmap = tables.get('cmap');
	if (!head || !cmap) throw new Error('no head or cmap table');
	const upem = u16(head.offset + 18);
	const variable = tables.has('fvar');

	// Prefer a full-repertoire Unicode subtable, as Chrome (through
	// HarfBuzz's cmap accelerator) does: (3,10) or (0,4..6), then (3,1) or
	// (0,0..3).
	const subtables = [];
	for (let i = 0, n = u16(cmap.offset + 2); i < n; i++) {
		const r = cmap.offset + 4 + 8 * i;
		subtables.push({ platform: u16(r), encoding: u16(r + 2), offset: cmap.offset + u32(r + 4) });
	}
	const rank = s =>
		s.platform === 3 && s.encoding === 10 ? 0
		: s.platform === 0 && s.encoding >= 4 && s.encoding <= 6 ? 1
		: s.platform === 3 && s.encoding === 1 ? 2
		: s.platform === 0 && s.encoding <= 3 ? 3
		: 9;
	const chosen = subtables.filter(s => rank(s) < 9).sort((x, y) => rank(x) - rank(y))[0];
	if (!chosen) throw new Unsupported('no Unicode cmap subtable');
	const o = chosen.offset;
	const format = u16(o);
	let maps;
	if (format === 0) {
		maps = cp => cp < 256 && (need(o + 6 + cp, 1), b[o + 6 + cp]) !== 0;
	} else if (format === 6) {
		const first = u16(o + 6);
		const n = u16(o + 8);
		maps = cp => cp >= first && cp < first + n && u16(o + 10 + 2 * (cp - first)) !== 0;
	} else if (format === 4) {
		const segX2 = u16(o + 6);
		const ends = o + 14;
		const starts = ends + segX2 + 2;
		const deltas = starts + segX2;
		const ranges = deltas + segX2;
		maps = cp => {
			if (cp > 0xffff) return false;
			for (let s = 0; s < segX2; s += 2) {
				if (cp > u16(ends + s)) continue;
				const start = u16(starts + s);
				if (cp < start) return false;
				const delta = u16(deltas + s);
				const rangeOffset = u16(ranges + s);
				if (rangeOffset === 0) return ((cp + delta) & 0xffff) !== 0;
				const glyph = u16(ranges + s + rangeOffset + 2 * (cp - start));
				return glyph !== 0 && ((glyph + delta) & 0xffff) !== 0;
			}
			return false;
		};
	} else if (format === 12) {
		const groups = u32(o + 12);
		maps = cp => {
			for (let g = 0; g < groups; g++) {
				const r = o + 16 + 12 * g;
				if (cp >= u32(r) && cp <= u32(r + 4)) return u32(r + 8) + (cp - u32(r)) !== 0;
			}
			return false;
		};
	} else {
		throw new Unsupported(`cmap format ${format}`);
	}
	return { upem, variable, maps };
}

// ---------------------------------------------------------- browser side

// Runs in the page: registers the font under `family`. Returns null, or the
// reason Chrome refused it.
async function loadFontInPage(base64, family) {
	const raw = atob(base64);
	const bytes = new Uint8Array(raw.length);
	for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
	try {
		const face = new FontFace(family, bytes.buffer);
		await face.load();
		document.fonts.add(face);
		return null;
	} catch (error) {
		return String(error && error.message ? error.message : error);
	}
}

// Runs in the page: the width of `text` at `size` px, by canvas and by a span.
function measureInPage(family, text, size) {
	const font = `${size}px "${family}"`;
	if (!document.fonts.check(font)) return { error: 'font not available' };
	const canvas = document.createElement('canvas');
	const context = canvas.getContext('2d');
	context.font = font;
	if (!context.font.includes(family)) return { error: `canvas refused font ${font}` };
	const canvasWidth = context.measureText(text).width;
	const span = document.createElement('span');
	span.style.cssText = `font-family:"${family}";font-size:${size}px;white-space:pre;position:absolute;left:0;top:0`;
	span.textContent = text;
	document.body.appendChild(span);
	const domWidth = span.getBoundingClientRect().width;
	span.remove();
	return { canvas: canvasWidth, dom: domWidth };
}

// ------------------------------------------------------------ node side

const installedPuppeteer = () => require('puppeteer/package.json').version;

async function openBrowser() {
	const { default: puppeteer } = await import(pathToFileURL(require.resolve('puppeteer')).href);
	// Sandbox off: common Linux hosts block the namespaces Chrome needs.
	// Every network request is refused; the page only ever holds data.
	const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox', '--font-render-hinting=none'] });
	const version = (await browser.version()).replace(/^[A-Za-z]+\//, '');
	if (version !== PIN.chrome) {
		await browser.close();
		throw new Error(`Chrome ${version} differs from the pin ${PIN.chrome} in tools/oracle/chrome/pin.json`);
	}
	const page = await browser.newPage();
	await page.setRequestInterception(true);
	page.on('request', request => (request.url().startsWith('data:') || request.url() === 'about:blank' ? request.continue() : request.abort()));
	await page.setContent('<!doctype html><html><head><style>body{margin:0}</style></head><body></body></html>');
	return { browser, page, version };
}

function versions() {
	const major = Number(process.versions.node.split('.')[0]);
	if (major < 22) throw new Error(`Node ${process.versions.node} is too old; Puppeteer ${PIN.puppeteer} needs Node 22 or later`);
	const puppeteer = installedPuppeteer();
	if (puppeteer !== PIN.puppeteer) throw new Error(`puppeteer ${puppeteer} differs from the pin ${PIN.puppeteer}`);
	return { extractor: EXTRACTOR_VERSION, tools: { chrome: PIN.chrome, puppeteer } };
}

function formatWidth(px) {
	const nearest = Math.round(px);
	if (Math.abs(px - nearest) <= INTEGER_TOLERANCE) return `width:${nearest === 0 ? 0 : nearest}`;
	return `width:${px.toFixed(6)}`;
}

async function answer(session, fonts, request) {
	const unsupported = reason => ({ status: 'unsupported', result: null, backend: '', detail: { option: reason } });
	const error = reason => ({ status: 'error', result: null, backend: BACKEND, detail: { error: reason } });
	if (request.kind !== 'width') return error(`unknown kind ${request.kind}`);
	const bad = request.options.find(option => !ALLOWED_OPTIONS.has(option));
	if (bad !== undefined) return unsupported(bad);

	let font = fonts.get(request.font);
	if (!font) {
		const bytes = fs.readFileSync(request.font);
		const family = `roc-font-oracle-${fonts.size}`;
		const refused = await session.page.evaluate(loadFontInPage, bytes.toString('base64'), family);
		font = { family, refused };
		if (!refused) {
			try {
				font.facts = fontFacts(bytes);
			} catch (e) {
				font.factsError = e;
			}
		}
		fonts.set(request.font, font);
	}
	if (font.refused) return error(`Chrome refused the font: ${font.refused}`);
	if (font.factsError instanceof Unsupported) return unsupported(font.factsError.message);
	if (font.factsError) return error(`font facts: ${font.factsError.message}`);
	const { upem, variable, maps } = font.facts;
	if (variable) return unsupported('variable font');
	const control = request.unicodes.find(cp => cp < 0x20 || (cp >= 0x7f && cp < 0xa0));
	if (control !== undefined) return unsupported(`control character U+${control.toString(16).toUpperCase().padStart(4, '0')}`);
	const unmapped = request.unicodes.find(cp => !maps(cp));
	if (unmapped !== undefined) {
		return unsupported(`U+${unmapped.toString(16).toUpperCase().padStart(4, '0')} not in cmap (Chrome would use a fallback font)`);
	}
	const text = String.fromCodePoint(...request.unicodes);
	const measured = await session.page.evaluate(measureInPage, font.family, text, upem);
	if (measured.error) return error(measured.error);
	return {
		status: 'ok',
		result: formatWidth(measured.dom),
		backend: BACKEND,
		detail: { canvas_px: measured.canvas, font_size_px: upem, span_px: measured.dom },
	};
}

async function main() {
	const command = process.argv[2] ?? '';
	if (command === 'versions') {
		process.stdout.write(JSON.stringify(versions()) + '\n');
		return 0;
	}
	if (command === 'run') {
		versions();
		const lines = [];
		for await (const line of readline.createInterface({ input: process.stdin })) {
			if (line.trim()) lines.push(JSON.parse(line));
		}
		if (lines.length === 0) return 0;
		const session = await openBrowser();
		const fonts = new Map();
		try {
			for (const request of lines) {
				let response;
				try {
					response = await answer(session, fonts, request);
				} catch (e) {
					response = { status: 'error', result: null, backend: BACKEND, detail: { error: String(e.message ?? e) } };
				}
				process.stdout.write(JSON.stringify(sortKeys(response)) + '\n');
			}
		} finally {
			await session.browser.close();
		}
		return 0;
	}
	process.stderr.write('usage: width.mjs versions | run < requests.jsonl\n');
	return 2;
}

// Sorted keys at every level, so output is byte-stable.
function sortKeys(value) {
	if (Array.isArray(value)) return value.map(sortKeys);
	if (value && typeof value === 'object') {
		return Object.fromEntries(Object.keys(value).sort().map(key => [key, sortKeys(value[key])]));
	}
	return value;
}

try {
	process.exitCode = await main();
} catch (e) {
	process.stderr.write(`width.mjs: ${e.message ?? e}\n`);
	process.exitCode = 1;
}
