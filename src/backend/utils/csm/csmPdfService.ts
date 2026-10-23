import { PDFDocument, PDFFont, PDFPage, StandardFonts, rgb } from "pdf-lib";
import { supabase } from "@/backend/config/database";
import {
  CHECKBOXES_TAGALOG,
  OFFICE_NAME_FIELD_TAGALOG,
  PAGE_HEIGHT_TAGALOG,
  PagedTextFieldSpec,
  SQD_COLUMN_X_TAGALOG,
  SQD_ROW_Y_TAGALOG,
  TEXT_FIELDS_TAGALOG,
} from "./csmPdfCoordinates";

const TEMPLATE_BUCKET = "documents";
// TEMPORARY: using the Tagalog template for all generation regardless of any
// language preference on the response. Swap back to csmform.pdf (English,
// single page) + the non-`_TAGALOG` coordinate exports once EN/TL selection
// is wired up properly.
// Template updated to the single-page Tagalog form — replaces the old
// 2-page csmform_tagalog.pdf. Page-indexed helpers below (getPage, the
// controlNo specs array, PagedPoint/page fields in csmPdfCoordinates.ts)
// are kept as-is (all `page: 0`) even though there's only one page now,
// per team decision to preserve the paged shape for future templates.
const TEMPLATE_PATH = "forms/csm/csm_onepage.pdf";

const TEXT_COLOR = rgb(0, 0, 0);
const LINE_HEIGHT_RATIO = 1.15;

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
  /** Denormalized office name (csm_response.office_name), used only for the
   * header placeholder — not required for the row to otherwise be valid. */
  office_name?: string | null;
}

/** Convert a top-based y (distance from top of page) to pdf-lib's bottom-left origin.
 * Uses the Tagalog page height (1008pt) — the single-page template's page height. */
function topToPdfY(top: number): number {
  return PAGE_HEIGHT_TAGALOG - top;
}

/** Looks up the correct PDFPage for a page-indexed field/checkbox. */
function getPage(pdfDoc: PDFDocument, pageIndex: number): PDFPage {
  return pdfDoc.getPage(pageIndex);
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
  font: PDFFont,
  spec: PagedTextFieldSpec,
  value: string | number | null | undefined
) {
  if (value === null || value === undefined || value === "") return;
  const text = String(value);
  const { size, text: fitted } = fitSingleLine(
    font,
    text,
    spec.maxWidth,
    spec.maxFontSize,
    spec.minFontSize
  );
  const page = getPage(pdfDoc, spec.page);
  page.drawText(fitted, {
    x: spec.x,
    // spec.top is the field's BASELINE (the underline's bottom edge), not a
    // box top — deliberately NOT offset by `size` here. Font-fit shrinking
    // changes `size` per value (e.g. a long region name vs. a short one),
    // and subtracting a variable size from a fixed top would make the
    // baseline drift upward as text shrinks, floating text above its
    // underline instead of sitting on it. Anchoring directly to a fixed
    // baseline keeps every value visually on its line regardless of size.
    y: topToPdfY(spec.top),
    size,
    font,
    color: TEXT_COLOR,
  });
}

/**
 * Draws single-line text horizontally centered within [boxLeft, boxRight],
 * shrinking to fit maxWidth like drawSingleLineField. Used for the office
 * name placeholder above the title, where names vary in length.
 */
function drawCenteredField(
  pdfDoc: PDFDocument,
  font: PDFFont,
  spec: {
    page: number;
    boxLeft: number;
    boxRight: number;
    top: number;
    maxWidth: number;
    maxFontSize: number;
    minFontSize: number;
  },
  value: string | null | undefined
) {
  if (!value) return;
  const { size, text: fitted } = fitSingleLine(
    font,
    value,
    spec.maxWidth,
    spec.maxFontSize,
    spec.minFontSize
  );
  const textWidth = font.widthOfTextAtSize(fitted, size);
  const boxCenter = (spec.boxLeft + spec.boxRight) / 2;
  const x = boxCenter - textWidth / 2;
  const page = getPage(pdfDoc, spec.page);
  page.drawText(fitted, {
    x,
    y: topToPdfY(spec.top) - size,
    size,
    font,
    color: TEXT_COLOR,
  });
}

function drawMultiLineField(
  pdfDoc: PDFDocument,
  font: PDFFont,
  spec: PagedTextFieldSpec,
  value: string | null | undefined
) {
  if (!value) return;
  const lineHeightRatio = spec.lineHeightRatio ?? LINE_HEIGHT_RATIO;
  const { size, lines } = fitMultiLine(
    font,
    value,
    spec.maxWidth,
    spec.maxHeight ?? 9999,
    spec.maxFontSize,
    spec.minFontSize,
    lineHeightRatio
  );
  const page = getPage(pdfDoc, spec.page);
  let y = topToPdfY(spec.top) - size;
  for (const line of lines) {
    page.drawText(line, { x: spec.x, y, size, font, color: TEXT_COLOR });
    y -= size * lineHeightRatio;
  }
}

/** Draws a checkmark (✓) as vector line segments, centered at (centerX, centerTop),
 * on the given page index. */
function drawCheckmark(
  pdfDoc: PDFDocument,
  pageIndex: number,
  centerX: number,
  centerTop: number,
  sizePt = 9
) {
  const page = getPage(pdfDoc, pageIndex);
  const cx = centerX;
  const cy = topToPdfY(centerTop);
  const half = sizePt / 2;
  // Short down-stroke then long up-stroke, classic checkmark proportions.
  const p1 = { x: cx - half, y: cy };
  const p2 = { x: cx - half / 4, y: cy - half * 0.7 };
  const p3 = { x: cx + half, y: cy + half * 0.8 };

  page.drawLine({ start: p1, end: p2, thickness: 1.3, color: TEXT_COLOR });
  page.drawLine({ start: p2, end: p3, thickness: 1.3, color: TEXT_COLOR });
}

function checkClientType(pdfDoc: PDFDocument, value: CsmResponseForPdf["client_type"]) {
  const pt = CHECKBOXES_TAGALOG.clientType[value];
  if (pt) drawCheckmark(pdfDoc, pt.page, pt.x, pt.y);
}

function checkSex(pdfDoc: PDFDocument, value: CsmResponseForPdf["sex"]) {
  if (!value) return;
  const pt = CHECKBOXES_TAGALOG.sex[value];
  if (pt) drawCheckmark(pdfDoc, pt.page, pt.x, pt.y);
}

function checkCC(pdfDoc: PDFDocument, group: "cc1" | "cc2" | "cc3", code: number) {
  const pt = (CHECKBOXES_TAGALOG[group] as Record<number, { x: number; y: number; page: number }>)[
    code
  ];
  if (pt) drawCheckmark(pdfDoc, pt.page, pt.x, pt.y);
}

function checkSqd(pdfDoc: PDFDocument, rowKey: keyof typeof SQD_ROW_Y_TAGALOG, phrase: string) {
  const colX = (SQD_COLUMN_X_TAGALOG as Record<string, number>)[phrase];
  const row = SQD_ROW_Y_TAGALOG[rowKey];
  if (colX === undefined || row === undefined) return;
  drawCheckmark(pdfDoc, row.page, colX, row.y);
}

function formatDate(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString("en-PH", { year: "numeric", month: "2-digit", day: "2-digit" });
}

async function loadTemplate(): Promise<PDFDocument> {
  const { data: templateBlob, error } = await supabase.storage
    .from(TEMPLATE_BUCKET)
    .download(TEMPLATE_PATH);

  if (error || !templateBlob) {
    throw new Error(`Failed to load CSM PDF template: ${error?.message ?? "not found"}`);
  }

  const templateBytes = new Uint8Array(await templateBlob.arrayBuffer());
  return PDFDocument.load(templateBytes);
}

/**
 * Fetches the CSM template from Supabase Storage and returns overlaid PDF bytes
 * for a single response row.
 *
 * TEMPORARY: always uses the Tagalog template (csm_onepage.pdf), regardless
 * of the response's actual language, until EN/TL selection is wired up.
 * `controlNo` is stamped by looping over `TEXT_FIELDS_TAGALOG.controlNo`
 * (an array of one spec now that the template is single-page) — kept as an
 * array/`.forEach()` rather than a single spec so this still works
 * unchanged if a future multi-page template reintroduces repeated
 * "Control No:" labels.
 */
export async function generateCsmPdf(response: CsmResponseForPdf): Promise<Uint8Array> {
  const pdfDoc = await loadTemplate();
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);

  // --- Text fields ---
  const controlNoSpecs = Array.isArray(TEXT_FIELDS_TAGALOG.controlNo)
    ? TEXT_FIELDS_TAGALOG.controlNo
    : [TEXT_FIELDS_TAGALOG.controlNo];
  controlNoSpecs.forEach((spec) => drawSingleLineField(pdfDoc, font, spec, response.control_no));

  drawCenteredField(pdfDoc, font, OFFICE_NAME_FIELD_TAGALOG, response.office_name);
  drawSingleLineField(
    pdfDoc,
    font,
    TEXT_FIELDS_TAGALOG.date as PagedTextFieldSpec,
    formatDate(response.transaction_date)
  );
  drawSingleLineField(pdfDoc, font, TEXT_FIELDS_TAGALOG.age as PagedTextFieldSpec, response.age ?? "N/A");
  drawSingleLineField(pdfDoc, font, TEXT_FIELDS_TAGALOG.region as PagedTextFieldSpec, response.region);
  drawSingleLineField(pdfDoc, font, TEXT_FIELDS_TAGALOG.service as PagedTextFieldSpec, response.service);
  drawSingleLineField(
    pdfDoc,
    font,
    TEXT_FIELDS_TAGALOG.email as PagedTextFieldSpec,
    response.email_address ?? ""
  );
  drawMultiLineField(
    pdfDoc,
    font,
    TEXT_FIELDS_TAGALOG.comments as PagedTextFieldSpec,
    response.comments ?? ""
  );

  // --- Checkboxes ---
  checkClientType(pdfDoc, response.client_type);
  checkSex(pdfDoc, response.sex ?? undefined);
  checkCC(pdfDoc, "cc1", response.cc1);
  checkCC(pdfDoc, "cc2", response.cc2);
  checkCC(pdfDoc, "cc3", response.cc3);

  (["sqd0", "sqd1", "sqd2", "sqd3", "sqd4", "sqd5", "sqd6", "sqd7", "sqd8"] as const).forEach(
    (key) => checkSqd(pdfDoc, key, response[key])
  );

  return pdfDoc.save();
}

/**
 * Calibration helper — NOT used in production. Loads the Tagalog template and
 * stamps a checkmark on every single checkbox coordinate in the map
 * simultaneously (client type x3, sex x2, cc1 x4, cc2 x5, cc3 x4, sqd0-8 x6 =
 * 54 marks, all on the single page now), ignoring the fact that a real
 * submission only ever selects one option per group. Use this while
 * trial-and-error tuning the `_TAGALOG` exports in csmPdfCoordinates.ts so
 * you can see every checkbox's position — and the still-unverified
 * office-name placement — in a single render instead of one at a time.
 */
export async function generateCalibrationPdf(): Promise<Uint8Array> {
  const pdfDoc = await loadTemplate();
  const calibrationFont = await pdfDoc.embedFont(StandardFonts.Helvetica);

  drawCenteredField(pdfDoc, calibrationFont, OFFICE_NAME_FIELD_TAGALOG, "City Treasurer's Office");

  Object.values(CHECKBOXES_TAGALOG.clientType).forEach((pt) =>
    drawCheckmark(pdfDoc, pt.page, pt.x, pt.y)
  );
  Object.values(CHECKBOXES_TAGALOG.sex).forEach((pt) => drawCheckmark(pdfDoc, pt.page, pt.x, pt.y));
  Object.values(CHECKBOXES_TAGALOG.cc1).forEach((pt) => drawCheckmark(pdfDoc, pt.page, pt.x, pt.y));
  Object.values(CHECKBOXES_TAGALOG.cc2).forEach((pt) => drawCheckmark(pdfDoc, pt.page, pt.x, pt.y));
  Object.values(CHECKBOXES_TAGALOG.cc3).forEach((pt) => drawCheckmark(pdfDoc, pt.page, pt.x, pt.y));

  (Object.keys(SQD_ROW_Y_TAGALOG) as (keyof typeof SQD_ROW_Y_TAGALOG)[]).forEach((rowKey) => {
    Object.keys(SQD_COLUMN_X_TAGALOG).forEach((phrase) => checkSqd(pdfDoc, rowKey, phrase));
  });

  return pdfDoc.save();
}