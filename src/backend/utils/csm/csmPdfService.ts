import { PDFDocument, PDFFont, PDFPage, StandardFonts, rgb } from "pdf-lib";
import { supabase } from "@/backend/config/database";
import {
  CHECKBOXES_TAGALOG,
  OFFICE_NAME_FIELD_TAGALOG,
  PAGE_HEIGHT_TAGALOG,
  PagedPoint,
  PagedTextFieldSpec,
  SQD_COLUMN_X_TAGALOG,
  SQD_ROW_Y_TAGALOG,
  TEMPLATE_PATH_TAGALOG,
  TEXT_FIELDS_TAGALOG,
} from "./csmPdfCoordinates";

const TEMPLATE_BUCKET = "documents";

const TEXT_COLOR = rgb(0, 0, 0);
const LINE_HEIGHT_RATIO = 1.15;

// ---------------------------------------------------------------------
// Per-language template config
// ---------------------------------------------------------------------
export type CsmPdfLang = "en" | "tl";

type SqdKey = "sqd0" | "sqd1" | "sqd2" | "sqd3" | "sqd4" | "sqd5" | "sqd6" | "sqd7" | "sqd8";

interface OfficeNameSpec {
  page: number;
  boxLeft: number;
  boxRight: number;
  top: number;
  maxWidth: number;
  maxFontSize: number;
  /** Smallest size to try on a single line before wrapping. */
  minSingleLineFontSize: number;
  /** Starting size when the name has to wrap. */
  wrapFontSize: number;
  /** Floor for the wrapped layout. */
  minFontSize: number;
  /** Top of the first line when wrapped (raised so 2 lines fit the slot). */
  wrappedTop: number;
  lineHeight: number;
  maxLines: number;
}

interface PdfTemplateConfig {
  templatePath: string;
  /** Page height in points; used to convert top-based y to pdf-lib's bottom-left origin. */
  pageHeight: number;
  checkboxes: {
    clientType: Record<string, PagedPoint>;
    sex: Record<string, PagedPoint>;
    cc1: Record<number, PagedPoint>;
    cc2: Record<number, PagedPoint>;
    cc3: Record<number, PagedPoint>;
  };
  sqdColumnX: Record<string, number>;
  sqdRowY: Record<SqdKey, { y: number; page: number }>;
  textFields: Record<string, PagedTextFieldSpec | PagedTextFieldSpec[]>;
  officeName: OfficeNameSpec;
}

const TAGALOG_TEMPLATE: PdfTemplateConfig = {
  templatePath: TEMPLATE_PATH_TAGALOG,
  pageHeight: PAGE_HEIGHT_TAGALOG,
  checkboxes: CHECKBOXES_TAGALOG,
  sqdColumnX: SQD_COLUMN_X_TAGALOG,
  sqdRowY: SQD_ROW_Y_TAGALOG,
  textFields: TEXT_FIELDS_TAGALOG,
  officeName: OFFICE_NAME_FIELD_TAGALOG,
};

/**
 * TODO(english-v2): the English template has not been migrated yet. Until its
 * template file + coordinate map exist, "en" falls back to the Tagalog template
 * so an English respondent still gets a PDF. Replace this entry with a real
 * English config (own templatePath, pageHeight and coordinates) when ready.
 */
const TEMPLATES: Record<CsmPdfLang, PdfTemplateConfig> = {
  tl: TAGALOG_TEMPLATE,
  en: TAGALOG_TEMPLATE,
};

export function resolvePdfLang(value: unknown): CsmPdfLang {
  return value === "en" || value === "tl" ? value : "tl";
}

export interface CsmResponseForPdf {
  control_no: string;
  client_type: "citizen" | "business" | "government";
  transaction_date: string; // ISO date
  sex?: "male" | "female" | null;
  age?: number | null;
  region: string;
  service: string;
  cc1: number;
  cc2: number;
  cc3: number;
  sqd0: string;
  sqd1: string;
  sqd2: string;
  sqd3: string;
  sqd4: string;
  sqd5: string;
  sqd6: string;
  sqd7: string;
  sqd8: string;
  comments?: string | null;
  email_address?: string | null;
  client_name?: string | null;
  contact_no?: string | null;
  /** Denormalized office name (csm_response.office_name), used only for the
   * header — not required for the row to otherwise be valid. */
  office_name?: string | null;
}

interface Fonts {
  regular: PDFFont;
  italic: PDFFont;
}

/** Convert a top-based y (distance from top of page) to pdf-lib's bottom-left origin. */
function topToPdfY(cfg: PdfTemplateConfig, top: number): number {
  return cfg.pageHeight - top;
}

/** Looks up the correct PDFPage for a page-indexed field/checkbox. */
function getPage(pdfDoc: PDFDocument, pageIndex: number): PDFPage {
  return pdfDoc.getPage(pageIndex);
}

/**
 * Standard PDF fonts only cover WinAnsi. Free text (client name, comments, office
 * name) can contain characters outside it, which would make drawText throw and
 * fail the whole PDF. Collapse whitespace/control characters and replace any
 * character the font can't encode with "?".
 */
function toEncodable(font: PDFFont, text: string): string {
  let out = "";
  for (const ch of text.replace(/\s+/g, " ").normalize("NFC")) {
    try {
      font.encodeText(ch);
      out += ch;
    } catch {
      out += "?";
    }
  }
  return out.trim();
}

/**
 * Shrinks font size to fit `text` within `maxWidth` at `font`, down to `minSize`.
 * Returns the chosen size and, if it still doesn't fit at minSize, a truncated
 * (ellipsized) version of the text.
 */
function fitSingleLine(
  font: PDFFont,
  text: string,
  maxWidth: number,
  maxSize: number,
  minSize: number
): { size: number; text: string } {
  let size = maxSize;
  while (size > minSize && font.widthOfTextAtSize(text, size) > maxWidth) {
    size -= 0.5;
  }
  if (font.widthOfTextAtSize(text, size) <= maxWidth) {
    return { size, text };
  }
  // Still doesn't fit at minSize — truncate with ellipsis.
  let truncated = text;
  while (
    truncated.length > 1 &&
    font.widthOfTextAtSize(truncated + "…", minSize) > maxWidth
  ) {
    truncated = truncated.slice(0, -1);
  }
  return { size: minSize, text: truncated + "…" };
}

/** Greedy word-wrap of `text` into lines that fit `maxWidth` at the given font/size. */
function wrapText(font: PDFFont, text: string, maxWidth: number, size: number): string[] {
  const words = text.split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let current = "";
  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    if (font.widthOfTextAtSize(candidate, size) <= maxWidth) {
      current = candidate;
    } else {
      if (current) lines.push(current);
      current = word;
    }
  }
  if (current) lines.push(current);
  return lines.length ? lines : [""];
}

/**
 * Fits multi-line `text` into a maxWidth x maxHeight box by shrinking font size
 * until all wrapped lines fit vertically, down to minSize. If it still overflows
 * at minSize, remaining lines are dropped and the last visible line gets an ellipsis.
 */
function fitMultiLine(
  font: PDFFont,
  text: string,
  maxWidth: number,
  maxHeight: number,
  maxSize: number,
  minSize: number,
  lineHeightRatio: number = LINE_HEIGHT_RATIO
): { size: number; lines: string[] } {
  let size = maxSize;
  let lines = wrapText(font, text, maxWidth, size);

  const fits = (s: number, ls: string[]) => ls.length * s * lineHeightRatio <= maxHeight;

  while (size > minSize && !fits(size, lines)) {
    size -= 0.5;
    lines = wrapText(font, text, maxWidth, size);
  }

  if (fits(size, lines)) {
    return { size, lines };
  }

  // Still overflowing at minSize: truncate to however many lines fit, ellipsize the last one.
  const maxLines = Math.max(1, Math.floor(maxHeight / (size * lineHeightRatio)));
  const visible = lines.slice(0, maxLines);
  let last = visible[visible.length - 1] ?? "";
  while (last.length > 1 && font.widthOfTextAtSize(last + "…", size) > maxWidth) {
    last = last.slice(0, -1);
  }
  visible[visible.length - 1] = last + "…";
  return { size, lines: visible };
}

function drawSingleLineField(
  pdfDoc: PDFDocument,
  cfg: PdfTemplateConfig,
  font: PDFFont,
  spec: PagedTextFieldSpec,
  value: string | number | null | undefined
) {
  if (value === null || value === undefined || value === "") return;
  const clean = toEncodable(font, String(value));
  if (!clean) return;
  const { size, text: fitted } = fitSingleLine(
    font,
    clean,
    spec.maxWidth,
    spec.maxFontSize,
    spec.minFontSize
  );
  const page = getPage(pdfDoc, spec.page);
  page.drawText(fitted, {
    x: spec.x,
    // spec.top is the field's BASELINE (just above the underline), not a box
    // top — deliberately NOT offset by `size`, so text stays on its line
    // whether it renders at maxFontSize or has shrunk to fit.
    y: topToPdfY(cfg, spec.top),
    size,
    font,
    color: TEXT_COLOR,
  });
}

/** Draws one line of text horizontally centered within [boxLeft, boxRight]. `top` is the top of the line. */
function drawCenteredLine(
  pdfDoc: PDFDocument,
  cfg: PdfTemplateConfig,
  font: PDFFont,
  spec: OfficeNameSpec,
  text: string,
  size: number,
  top: number
) {
  const textWidth = font.widthOfTextAtSize(text, size);
  const x = (spec.boxLeft + spec.boxRight) / 2 - textWidth / 2;
  getPage(pdfDoc, spec.page).drawText(text, {
    x,
    y: topToPdfY(cfg, top) - size,
    size,
    font,
    color: TEXT_COLOR,
  });
}

/**
 * Office name under the printed header: centered, italic, smaller than the
 * header. Fits on one line when it can (down to minSingleLineFontSize);
 * otherwise wraps onto up to `maxLines` centered lines; only if that still
 * overflows does it shrink further and ellipsize the last line.
 */
function drawOfficeName(
  pdfDoc: PDFDocument,
  cfg: PdfTemplateConfig,
  font: PDFFont,
  spec: OfficeNameSpec,
  value: string | null | undefined
) {
  if (!value) return;
  const clean = toEncodable(font, value);
  if (!clean) return;
  const width = (t: string, size: number) => font.widthOfTextAtSize(t, size);

  // 1. Single line.
  let size = spec.maxFontSize;
  while (size > spec.minSingleLineFontSize && width(clean, size) > spec.maxWidth) size -= 0.5;
  if (width(clean, size) <= spec.maxWidth) {
    drawCenteredLine(pdfDoc, cfg, font, spec, clean, size, spec.top);
    return;
  }

  // 2. Wrap, shrinking only until it fits in maxLines.
  size = spec.wrapFontSize;
  let lines = wrapText(font, clean, spec.maxWidth, size);
  while (lines.length > spec.maxLines && size > spec.minFontSize) {
    size -= 0.5;
    lines = wrapText(font, clean, spec.maxWidth, size);
  }

  // Balance a two-line wrap: narrow the wrap width as far as it still gives
  // two lines, so the text splits evenly instead of leaving a lone last word.
  if (lines.length === 2) {
    let lo = Math.max(...clean.split(" ").map((w) => width(w, size)));
    let hi = spec.maxWidth;
    for (let i = 0; i < 12; i++) {
      const mid = (lo + hi) / 2;
      if (wrapText(font, clean, mid, size).length <= 2) hi = mid;
      else lo = mid;
    }
    lines = wrapText(font, clean, hi, size);
  }

  // 3. Still too many lines (or a single word wider than the box): ellipsize.
  if (lines.length > spec.maxLines) {
    const kept = lines.slice(0, spec.maxLines);
    // Fold the overflow into the last kept line so the ellipsis marks the cut.
    kept[kept.length - 1] = lines.slice(spec.maxLines - 1).join(" ");
    lines = kept;
  }
  lines.forEach((line, i) => {
    const fit = fitSingleLine(font, line, spec.maxWidth, size, Math.min(size, spec.minFontSize));
    drawCenteredLine(pdfDoc, cfg, font, spec, fit.text, fit.size, spec.wrappedTop + i * spec.lineHeight);
  });
}

function drawMultiLineField(
  pdfDoc: PDFDocument,
  cfg: PdfTemplateConfig,
  font: PDFFont,
  spec: PagedTextFieldSpec,
  value: string | null | undefined
) {
  if (!value) return;
  const clean = toEncodable(font, value);
  if (!clean) return;
  const lineHeightRatio = spec.lineHeightRatio ?? LINE_HEIGHT_RATIO;
  const { size, lines } = fitMultiLine(
    font,
    clean,
    spec.maxWidth,
    spec.maxHeight ?? 9999,
    spec.maxFontSize,
    spec.minFontSize,
    lineHeightRatio
  );
  const page = getPage(pdfDoc, spec.page);
  let y = topToPdfY(cfg, spec.top) - size;
  for (const line of lines) {
    page.drawText(line, { x: spec.x, y, size, font, color: TEXT_COLOR });
    y -= size * lineHeightRatio;
  }
}

/** Draws a checkmark (✓) as vector line segments, centered at (centerX, centerTop),
 * on the given page index. */
function drawCheckmark(
  pdfDoc: PDFDocument,
  cfg: PdfTemplateConfig,
  pageIndex: number,
  centerX: number,
  centerTop: number,
  sizePt = 9
) {
  const page = getPage(pdfDoc, pageIndex);
  const cx = centerX;
  const cy = topToPdfY(cfg, centerTop);
  const half = sizePt / 2;
  // Short down-stroke then long up-stroke, classic checkmark proportions.
  const p1 = { x: cx - half, y: cy };
  const p2 = { x: cx - half / 4, y: cy - half * 0.7 };
  const p3 = { x: cx + half, y: cy + half * 0.8 };

  page.drawLine({ start: p1, end: p2, thickness: 1.3, color: TEXT_COLOR });
  page.drawLine({ start: p2, end: p3, thickness: 1.3, color: TEXT_COLOR });
}

function checkClientType(pdfDoc: PDFDocument, cfg: PdfTemplateConfig, value: CsmResponseForPdf["client_type"]) {
  const pt = cfg.checkboxes.clientType[value];
  if (pt) drawCheckmark(pdfDoc, cfg, pt.page, pt.x, pt.y);
}

function checkSex(pdfDoc: PDFDocument, cfg: PdfTemplateConfig, value: CsmResponseForPdf["sex"]) {
  if (!value) return;
  const pt = cfg.checkboxes.sex[value];
  if (pt) drawCheckmark(pdfDoc, cfg, pt.page, pt.x, pt.y);
}

function checkCC(pdfDoc: PDFDocument, cfg: PdfTemplateConfig, group: "cc1" | "cc2" | "cc3", code: number) {
  const pt = cfg.checkboxes[group][code];
  if (pt) drawCheckmark(pdfDoc, cfg, pt.page, pt.x, pt.y);
}

function checkSqd(pdfDoc: PDFDocument, cfg: PdfTemplateConfig, rowKey: SqdKey, phrase: string) {
  const colX = cfg.sqdColumnX[phrase];
  const row = cfg.sqdRowY[rowKey];
  if (colX === undefined || row === undefined) return;
  drawCheckmark(pdfDoc, cfg, row.page, colX, row.y);
}

function formatDate(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString("en-PH", { year: "numeric", month: "2-digit", day: "2-digit" });
}

async function loadTemplate(cfg: PdfTemplateConfig): Promise<PDFDocument> {
  const { data: templateBlob, error } = await supabase.storage
    .from(TEMPLATE_BUCKET)
    .download(cfg.templatePath);

  if (error || !templateBlob) {
    throw new Error(
      `Failed to load CSM PDF template (${cfg.templatePath}): ${error?.message ?? "not found"}`
    );
  }

  const templateBytes = new Uint8Array(await templateBlob.arrayBuffer());
  return PDFDocument.load(templateBytes);
}

const SQD_KEYS = ["sqd0", "sqd1", "sqd2", "sqd3", "sqd4", "sqd5", "sqd6", "sqd7", "sqd8"] as const;

/**
 * Overlays one response onto an already-loaded template document. Split out
 * from generateCsmPdf so it can be exercised without Supabase (scripts/tests).
 */
export async function fillCsmPdf(
  pdfDoc: PDFDocument,
  response: CsmResponseForPdf,
  lang: CsmPdfLang = "tl"
): Promise<Uint8Array> {
  const cfg = TEMPLATES[lang] ?? TEMPLATES.tl;
  const fonts: Fonts = {
    regular: await pdfDoc.embedFont(StandardFonts.Helvetica),
    italic: await pdfDoc.embedFont(StandardFonts.HelveticaOblique),
  };
  const { regular: font } = fonts;
  const tf = cfg.textFields;

  // --- Text fields ---
  const controlNoSpecs = Array.isArray(tf.controlNo) ? tf.controlNo : [tf.controlNo];
  controlNoSpecs.forEach((spec) =>
    drawSingleLineField(pdfDoc, cfg, font, spec, response.control_no)
  );

  // Office name: smaller italic text under the printed "CITY GOVERNMENT OF SAN PABLO" (wraps to 2 lines if long).
  drawOfficeName(pdfDoc, cfg, fonts.italic, cfg.officeName, response.office_name);

  drawSingleLineField(pdfDoc, cfg, font, tf.date as PagedTextFieldSpec, formatDate(response.transaction_date));
  drawSingleLineField(pdfDoc, cfg, font, tf.age as PagedTextFieldSpec, response.age ?? "N/A");
  drawSingleLineField(pdfDoc, cfg, font, tf.region as PagedTextFieldSpec, response.region);
  drawSingleLineField(pdfDoc, cfg, font, tf.service as PagedTextFieldSpec, response.service);
  drawMultiLineField(pdfDoc, cfg, font, tf.comments as PagedTextFieldSpec, response.comments ?? "");
  drawSingleLineField(pdfDoc, cfg, font, tf.clientName as PagedTextFieldSpec, response.client_name);
  drawSingleLineField(pdfDoc, cfg, font, tf.contactNo as PagedTextFieldSpec, response.contact_no);
  drawSingleLineField(pdfDoc, cfg, font, tf.email as PagedTextFieldSpec, response.email_address);

  // --- Checkboxes ---
  checkClientType(pdfDoc, cfg, response.client_type);
  checkSex(pdfDoc, cfg, response.sex ?? undefined);
  checkCC(pdfDoc, cfg, "cc1", response.cc1);
  checkCC(pdfDoc, cfg, "cc2", response.cc2);
  checkCC(pdfDoc, cfg, "cc3", response.cc3);
  SQD_KEYS.forEach((key) => checkSqd(pdfDoc, cfg, key, response[key]));

  return pdfDoc.save();
}

/**
 * Fetches the CSM template for `lang` from Supabase Storage and returns the
 * overlaid PDF bytes for a single response row.
 *
 * `lang` is the language the respondent chose on the form. It is used only to
 * pick the template; it is not stored. English currently falls back to the
 * Tagalog template (see TEMPLATES).
 */
export async function generateCsmPdf(
  response: CsmResponseForPdf,
  lang: CsmPdfLang = "tl"
): Promise<Uint8Array> {
  const cfg = TEMPLATES[lang] ?? TEMPLATES.tl;
  const pdfDoc = await loadTemplate(cfg);
  return fillCsmPdf(pdfDoc, response, lang);
}

/**
 * Calibration helper — NOT used in production. Loads the template for `lang`
 * and stamps a checkmark on every checkbox coordinate simultaneously, plus
 * sample text in every field, so every position can be checked in one render.
 */
export async function generateCalibrationPdf(lang: CsmPdfLang = "tl"): Promise<Uint8Array> {
  const cfg = TEMPLATES[lang] ?? TEMPLATES.tl;
  const pdfDoc = await loadTemplate(cfg);
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const italic = await pdfDoc.embedFont(StandardFonts.HelveticaOblique);
  const tf = cfg.textFields;

  drawOfficeName(pdfDoc, cfg, italic, cfg.officeName, "City Treasurer's Office");
  drawSingleLineField(pdfDoc, cfg, font, tf.clientName as PagedTextFieldSpec, "Juan Dela Cruz");
  drawSingleLineField(pdfDoc, cfg, font, tf.contactNo as PagedTextFieldSpec, "0917 123 4567");
  drawSingleLineField(pdfDoc, cfg, font, tf.email as PagedTextFieldSpec, "juan@email.com");

  const mark = (pt: PagedPoint) => drawCheckmark(pdfDoc, cfg, pt.page, pt.x, pt.y);
  Object.values(cfg.checkboxes.clientType).forEach(mark);
  Object.values(cfg.checkboxes.sex).forEach(mark);
  Object.values(cfg.checkboxes.cc1).forEach(mark);
  Object.values(cfg.checkboxes.cc2).forEach(mark);
  Object.values(cfg.checkboxes.cc3).forEach(mark);

  (Object.keys(cfg.sqdRowY) as SqdKey[]).forEach((rowKey) => {
    Object.keys(cfg.sqdColumnX).forEach((phrase) => checkSqd(pdfDoc, cfg, rowKey, phrase));
  });

  return pdfDoc.save();
}