/**
 * Coordinate map for the CSM (Client Satisfaction Measurement) PDF templates.
 *
 * Source templates: Supabase Storage bucket "documents", path "forms/csm/<template file>"
 * Origin note: all coordinates below are TOP-based (distance from top of page, in points),
 * matching how they were measured off the template. Convert to pdf-lib's bottom-left
 * origin at draw time with `topToPdfY()` in csmPdfService.ts.
 *
 * If a template file is ever replaced/re-exported, re-derive its map before trusting it.
 */

export const PAGE_WIDTH = 612;
export const PAGE_HEIGHT = 936;

/** Checkbox center point. Unlike TextFieldSpec, `y` here is the vertical CENTER
 * of the checkbox (top-based, i.e. distance from top of page), not a text baseline top. */
export interface Point {
  x: number;
  y: number;
}

export interface TextFieldSpec {
  x: number;
  top: number;
  maxWidth: number;
  maxFontSize: number;
  minFontSize: number;
  /** Only 'comments' is multi-line; everything else is single-line. */
  multiline?: boolean;
  maxHeight?: number; // only relevant when multiline
  /** Line spacing multiplier for multiline fields, e.g. 1.15 = tight, 1.5 = airy.
   * Defaults to 1.15 in csmPdfService.ts if omitted. Only relevant when multiline. */
  lineHeightRatio?: number;
}

/* ============================================================================
 * ENGLISH TEMPLATE (csmform.pdf, 612 x 936) — LEGACY, NOT USED YET.
 * To be replaced by a v2 English template (same layout as the Tagalog v2,
 * with Client Name / Contact No. fields) in a later pass.
 * ==========================================================================*/

/** Checkbox center points, keyed by field group -> option value. */
export const CHECKBOXES = {
  clientType: {
    citizen: { x: 95.9, y: 150 } as Point,
    business: { x: 143.0, y: 150 } as Point,
    government: { x: 198.2, y: 150 } as Point,
  },
  sex: {
    male: { x: 206.8, y: 172 } as Point,
    female: { x: 245.6, y: 172 } as Point,
  },
  cc1: {
    1: { x: 82, y: 300.45 } as Point,
    2: { x: 82, y: 313.0 } as Point,
    3: { x: 82, y: 326.7 } as Point,
    4: { x: 82, y: 338.55 } as Point,
  },
  cc2: {
    1: { x: 82, y: 372.7 } as Point,
    2: { x: 82, y: 386.85 } as Point,
    3: { x: 82, y: 396.65 } as Point,
    4: { x: 253.9, y: 373.15 } as Point,
    5: { x: 253.9, y: 386.15 } as Point, // N/A
  },
  cc3: {
    1: { x: 82, y: 432.0 } as Point,
    2: { x: 82, y: 444.6 } as Point,
    3: { x: 216.9, y: 434.15 } as Point,
    4: { x: 217.8, y: 443.7 } as Point, // N/A
  },
} as const;

/** SQD table: 6 answer columns (center-x) x 9 rows (center-y), in points. */
export const SQD_COLUMN_X = {
  "Strongly Disagree": 273.25,
  Disagree: 325.25,
  "Neither Agree nor Disagree": 385.5,
  Agree: 439.5,
  "Strongly Agree": 483.65,
  "Not Applicable": 531.9,
} as const;

export const SQD_ROW_Y: Record<
  "sqd0" | "sqd1" | "sqd2" | "sqd3" | "sqd4" | "sqd5" | "sqd6" | "sqd7" | "sqd8",
  number
> = {
  sqd0: 544.75,
  sqd1: 571.9,
  sqd2: 602.65,
  sqd3: 632.85,
  sqd4: 657.5,
  sqd5: 685.5,
  sqd6: 713.5,
  sqd7: 742.3,
  sqd8: 776.65,
};

/** Free-text field placements. */
export const TEXT_FIELDS: Record<string, TextFieldSpec> = {
  controlNo: { x: 87, top: 16, maxWidth: 60, maxFontSize: 11, minFontSize: 6 },
  date: { x: 68, top: 163.9, maxWidth: 100, maxFontSize: 11, minFontSize: 6 },
  age: { x: 350, top: 165.9, maxWidth: 35, maxFontSize: 11, minFontSize: 6 },
  region: { x: 135, top: 185.5, maxWidth: 100, maxFontSize: 11, minFontSize: 6 },
  service: { x: 333, top: 185.5, maxWidth: 200, maxFontSize: 11, minFontSize: 6 },
  email: { x: 155, top: 870.1, maxWidth: 245, maxFontSize: 11, minFontSize: 6 },
  comments: {
    x: 31,
    top: 825,
    maxWidth: 545,
    maxHeight: 45,
    maxFontSize: 11,
    minFontSize: 6,
    multiline: true,
    lineHeightRatio: 2,
  },
};

/**
 * Office name placeholder area (English template) — drawn horizontally centered
 * within [boxLeft, boxRight] by csmPdfService.ts.
 */
export const OFFICE_NAME_FIELD = {
  boxLeft: 195.6,
  boxRight: 419.6,
  top: 42,
  maxWidth: 524,
  maxFontSize: 22,
  minFontSize: 22,
} as const;

/* ============================================================================
 * TAGALOG TEMPLATE v2 — 1 PAGE (csm-tl-v2.pdf)
 *
 * Source template: Supabase Storage bucket "documents", path
 * "forms/csm/csm-tl-v2.pdf". Replaces csm_onepage.pdf.
 *
 * Page size: 612 x 1008pt, single page.
 *
 * What changed from csm_onepage.pdf:
 *  - Bottom block redesigned: two ruled comment lines, then a row with
 *    "Pangalan ng kliyente" + "Numero ng telepono", then the email row.
 *  - "MARAMING SALAMAT!" moved to the very bottom.
 *  - Header "CITY GOVERNMENT OF SAN PABLO" is printed on the template; the
 *    office name is drawn BELOW it in smaller italic text.
 *  - Checkbox / SQD positions are essentially unchanged (shifted <= 1pt).
 *
 * Derived from the template's text layer (pdfplumber word boxes) and vector
 * geometry (rects/lines), and checkbox centers were cross-checked against a
 * 288-dpi raster of the template (pixel centers matched glyph centers within
 * 0.1pt). Not yet eyeballed on a production render.
 *
 * `page` fields are kept (always 0) to preserve the paged data shape used by
 * csmPdfService.ts.
 * ==========================================================================*/

export const TEMPLATE_PATH_TAGALOG = "forms/csm/csm-tl-v2.pdf";
export const PAGE_WIDTH_TAGALOG = 612;
export const PAGE_HEIGHT_TAGALOG = 1008;
export const PAGE_COUNT_TAGALOG = 1;

/** Same shape as Point, plus a page index. */
export interface PagedPoint extends Point {
  page: number;
}

/** Same shape as TextFieldSpec, plus a page index. */
export interface PagedTextFieldSpec extends TextFieldSpec {
  page: number;
}

/** Checkbox centers (measured from the rendered template). */
export const CHECKBOXES_TAGALOG = {
  clientType: {
    citizen: { x: 104.3, y: 157.1, page: 0 } as PagedPoint,
    business: { x: 172.6, y: 157.1, page: 0 } as PagedPoint,
    government: { x: 227.4, y: 157.1, page: 0 } as PagedPoint,
  },
  sex: {
    male: { x: 225.7, y: 177.9, page: 0 } as PagedPoint,
    female: { x: 268.4, y: 177.9, page: 0 } as PagedPoint,
  },
  cc1: {
    1: { x: 85.4, y: 305.5, page: 0 } as PagedPoint,
    2: { x: 85.4, y: 315.7, page: 0 } as PagedPoint,
    3: { x: 85.4, y: 325.7, page: 0 } as PagedPoint,
    4: { x: 85.4, y: 335.9, page: 0 } as PagedPoint,
  },
  cc2: {
    1: { x: 85.4, y: 383.3, page: 0 } as PagedPoint,
    2: { x: 85.4, y: 393.5, page: 0 } as PagedPoint,
    3: { x: 85.4, y: 404.1, page: 0 } as PagedPoint,
    4: { x: 256.6, y: 383.3, page: 0 } as PagedPoint,
    5: { x: 256.6, y: 393.5, page: 0 } as PagedPoint, // N/A
  },
  cc3: {
    1: { x: 85.4, y: 441.7, page: 0 } as PagedPoint,
    2: { x: 85.4, y: 452.7, page: 0 } as PagedPoint,
    3: { x: 255.6, y: 441.7, page: 0 } as PagedPoint,
    4: { x: 256.2, y: 452.7, page: 0 } as PagedPoint, // N/A
  },
} as const;

/** SQD table: 6 answer columns (center-x). Midpoints of the vertical gridlines
 * at x = 252, 303, 355, 411, 463, 510, 558. */
export const SQD_COLUMN_X_TAGALOG = {
  "Strongly Disagree": 277.5,
  Disagree: 329,
  "Neither Agree nor Disagree": 383,
  Agree: 437,
  "Strongly Agree": 486.5,
  "Not Applicable": 534,
} as const;

/** SQD row centers (center-y). Midpoints between horizontal gridlines at
 * 587.3, 614.3, 642.3, 678.4, 705.4, 741.4, 777.4, 804.4, 840.4, 876.4. */
export const SQD_ROW_Y_TAGALOG: Record<
  "sqd0" | "sqd1" | "sqd2" | "sqd3" | "sqd4" | "sqd5" | "sqd6" | "sqd7" | "sqd8",
  { y: number; page: number }
> = {
  sqd0: { y: 600.8, page: 0 },
  sqd1: { y: 628.3, page: 0 },
  sqd2: { y: 660.4, page: 0 },
  sqd3: { y: 691.9, page: 0 },
  sqd4: { y: 723.4, page: 0 },
  sqd5: { y: 759.4, page: 0 },
  sqd6: { y: 790.9, page: 0 },
  sqd7: { y: 822.4, page: 0 },
  sqd8: { y: 858.4, page: 0 },
};

/**
 * IMPORTANT — `top` semantics differ between single-line and multiline specs:
 *  - Single-line specs (controlNo, date, age, region, service, clientName,
 *    contactNo, email): `top` is the field's BASELINE — just above the bottom
 *    edge of the template's ruled underline for that field. drawSingleLineField()
 *    draws at this y with no size-dependent offset.
 *  - The multiline spec (comments): `top` is a box TOP (first line's starting
 *    position); the first baseline lands at top + fontSize.
 *
 * Underlines on the template (x range @ y):
 *   date 64–121 @182.4 · age 386–443 @182.4 · region 74–141 @201.3 ·
 *   service 303–465 @201.3 · comment lines 36–476.5 @914.8 and @933.1 ·
 *   client name 169–301 @950.9 · contact no. 440–562 @950.9 · email 143–477 @969.4
 */
export const TEXT_FIELDS_TAGALOG: Record<string, PagedTextFieldSpec | PagedTextFieldSpec[]> = {
  controlNo: [{ x: 86, top: 24, maxWidth: 60, maxFontSize: 14, minFontSize: 6, page: 0 }],
  date: { x: 64, top: 181.7, maxWidth: 55, maxFontSize: 10, minFontSize: 6, page: 0 },
  age: { x: 396, top: 181.7, maxWidth: 45, maxFontSize: 10, minFontSize: 6, page: 0 },
  region: { x: 74, top: 200.6, maxWidth: 95, maxFontSize: 10, minFontSize: 6, page: 0 },
  service: { x: 302.6, top: 200.6, maxWidth: 270, maxFontSize: 8, minFontSize: 6, page: 0 },
  comments: {
    // Two ruled lines: baselines should sit just above y=914.8 and y=933.1
    // (18.3pt apart). First baseline = top + size = 905.1 + 9 = 914.1.
    // lineHeightRatio 2.03 at 9pt gives the 18.3pt line pitch.
    x: 36,
    top: 905.1,
    maxWidth: 440,
    maxHeight: 40,
    maxFontSize: 9,
    minFontSize: 6,
    multiline: true,
    lineHeightRatio: 2.03,
    page: 0,
  },
  clientName: { x: 172, top: 950.2, maxWidth: 126, maxFontSize: 9, minFontSize: 6, page: 0 },
  contactNo: { x: 443, top: 950.2, maxWidth: 117, maxFontSize: 9, minFontSize: 6, page: 0 },
  email: { x: 145, top: 968.7, maxWidth: 330, maxFontSize: 9, minFontSize: 6, page: 0 },
};

/**
 * Office name — drawn centered BELOW the printed "CITY GOVERNMENT OF SAN PABLO"
 * header (printed text spans x=158.8–439.7, top=37.2–53.2, center x≈299.25), in
 * smaller italic text. The slot is the gap between the header (bottom 53.2) and
 * the "TULUNGAN MO KAMI..." line (top 78.7), i.e. ~25pt tall.
 *
 * The ARTA approval box sits at x=459–598, top=14.4–66.9, so the horizontal
 * range is kept symmetric around the header's center and stops at x=452.5
 * (boxLeft/boxRight below) so a long name can never run into that box.
 *
 * Layout rules (see drawOfficeName in csmPdfService.ts):
 *  1. Single line: shrink from maxFontSize down to minSingleLineFontSize.
 *     `top` is the TOP of the text line (baseline = top + size).
 *  2. If it still doesn't fit, WRAP onto up to `maxLines` lines at
 *     wrapFontSize (shrinking down to minFontSize if needed). The first line
 *     starts at `wrappedTop` (raised slightly so two lines fit in the slot)
 *     and each following line is `lineHeight` lower.
 *  3. If it still doesn't fit in `maxLines`, the last line is ellipsized.
 */
export const OFFICE_NAME_FIELD_TAGALOG = {
  page: 0,
  boxLeft: 146,
  boxRight: 452.5,
  top: 57,
  maxWidth: 306.5, // boxRight - boxLeft
  maxFontSize: 11,
  minSingleLineFontSize: 9,
  wrapFontSize: 9,
  minFontSize: 8,
  wrappedTop: 54.5,
  lineHeight: 10,
  maxLines: 2,
} as const;