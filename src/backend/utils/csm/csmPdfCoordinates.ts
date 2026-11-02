/**
 * Coordinate map for the CSM (Client Satisfaction Measurement) PDF templates.
 *
 * Source templates: Supabase Storage bucket "documents", path "forms/csm/<template file>"
 * (csm-tl-v2.pdf, csm-en-v2.pdf)
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

/** Single-line field drawn at one fixed font size (no shrink-to-fit, no width
 * limit). For fields with plenty of room, e.g. the control number. `top` is the
 * baseline, same as single-line PagedTextFieldSpec. */
export interface PagedFixedFieldSpec {
  x: number;
  top: number;
  fontSize: number;
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
export const TEXT_FIELDS_TAGALOG: Record<
  string,
  PagedTextFieldSpec | PagedTextFieldSpec[] | PagedFixedFieldSpec | PagedFixedFieldSpec[]
> = {
  controlNo: [{ x: 90, top: 24, fontSize: 10, page: 0 }],
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

/* ============================================================================
 * ENGLISH TEMPLATE v2 — 1 PAGE (csm-en-v2.pdf)
 *
 * Source template: Supabase Storage bucket "documents", path
 * "forms/csm/csm-en-v2.pdf" (the "Online Version" of the ARTA form).
 * Replaces the legacy csmform.pdf map.
 *
 * Page size: 612 x 936pt, single page.
 *
 * Derived the same way as the Tagalog v2 map: text layer (word boxes) and
 * vector geometry (table gridlines, underlines), with checkbox centers
 * cross-checked against a 288-dpi raster (glyph centers within 0.4pt of the
 * pixel centers; the pixel values are used below). Not yet eyeballed on a
 * production render.
 *
 * Layout notes vs the Tagalog template:
 *  - Same field set (incl. Client Name / Contact No.), different positions.
 *  - Page is 936pt tall, so the bottom block is higher up.
 *  - SQD table columns are NOT evenly spaced (the Neither column is wider).
 *  - The ARTA approval box is at x=444–586, top=11–67. "(Online Version)"
 *    is printed at the left, x=37, top=40–48.
 *  - Header "CITY GOVERNMENT OF SAN PABLO" spans x=158.7–439.5, top=36.2–52.2
 *    (center x≈299.1); the next printed line ("HELP US SERVE YOU BETTER!")
 *    starts at top=82, leaving ~30pt for the office name.
 *
 * Underlines (x range @ y): date 57–133 @165.2 · age 343–393 @165.2 ·
 * region 112–220 @184.4 · service 312–530 @184.4 · comment lines 36–574.5
 * @793.2 and @814.9 · client name 127–271 @831.6 · contact no. 390–499 @831.6
 * · email 126.5–441 @848.8. Single-line `top` values are baselines just above
 * these; the comments `top` is a box top (see the Tagalog notes).
 * ==========================================================================*/

export const TEMPLATE_PATH_ENGLISH = "forms/csm/csm-en-v2.pdf";
export const PAGE_WIDTH_ENGLISH = 612;
export const PAGE_HEIGHT_ENGLISH = 936;
export const PAGE_COUNT_ENGLISH = 1;

export const CHECKBOXES_ENGLISH = {
  clientType: {
    citizen: { x: 81.3, y: 142.0, page: 0 } as PagedPoint,
    business: { x: 122.7, y: 142.0, page: 0 } as PagedPoint,
    government: { x: 171.9, y: 142.0, page: 0 } as PagedPoint,
  },
  sex: {
    male: { x: 202.0, y: 161.2, page: 0 } as PagedPoint,
    female: { x: 236.7, y: 161.2, page: 0 } as PagedPoint,
  },
  cc1: {
    1: { x: 85.4, y: 270.5, page: 0 } as PagedPoint,
    2: { x: 85.4, y: 282.5, page: 0 } as PagedPoint,
    3: { x: 85.9, y: 294.3, page: 0 } as PagedPoint,
    4: { x: 85.4, y: 306.1, page: 0 } as PagedPoint,
  },
  cc2: {
    1: { x: 85.4, y: 335.9, page: 0 } as PagedPoint,
    2: { x: 85.9, y: 348.3, page: 0 } as PagedPoint,
    3: { x: 85.9, y: 360.9, page: 0 } as PagedPoint,
    4: { x: 256.0, y: 336.3, page: 0 } as PagedPoint,
    5: { x: 256.0, y: 348.4, page: 0 } as PagedPoint, // N/A
  },
  cc3: {
    1: { x: 85.9, y: 390.7, page: 0 } as PagedPoint,
    2: { x: 85.9, y: 403.3, page: 0 } as PagedPoint,
    3: { x: 220.0, y: 391.1, page: 0 } as PagedPoint,
    4: { x: 220.0, y: 403.5, page: 0 } as PagedPoint, // N/A
  },
} as const;

/** SQD table: 6 answer columns (center-x). Midpoints of the vertical gridlines
 * at x = 251.9, 302.9, 355.5, 422.9, 462.9, 511.0, 558.8. */
export const SQD_COLUMN_X_ENGLISH = {
  "Strongly Disagree": 277.4,
  Disagree: 329.2,
  "Neither Agree nor Disagree": 389.2,
  Agree: 442.9,
  "Strongly Agree": 487.0,
  "Not Applicable": 534.9,
} as const;

/** SQD row centers (center-y). Midpoints between horizontal gridlines at
 * 486.3, 513.1, 539.9, 574.9, 601.7, 625.2, 658.5, 682.2, 717.2, 752.0. */
export const SQD_ROW_Y_ENGLISH: Record<
  "sqd0" | "sqd1" | "sqd2" | "sqd3" | "sqd4" | "sqd5" | "sqd6" | "sqd7" | "sqd8",
  { y: number; page: number }
> = {
  sqd0: { y: 500.2, page: 0 },
  sqd1: { y: 527.0, page: 0 },
  sqd2: { y: 557.9, page: 0 },
  sqd3: { y: 588.8, page: 0 },
  sqd4: { y: 614.0, page: 0 },
  sqd5: { y: 642.4, page: 0 },
  sqd6: { y: 670.9, page: 0 },
  sqd7: { y: 700.2, page: 0 },
  sqd8: { y: 735.1, page: 0 },
};

export const TEXT_FIELDS_ENGLISH: Record<
  string,
  PagedTextFieldSpec | PagedTextFieldSpec[] | PagedFixedFieldSpec | PagedFixedFieldSpec[]
> = {
  // "Control No:" label ends at x=86.8, bottom=25.7.
  controlNo: [{ x: 91, top: 24, fontSize: 10, page: 0 }],
  date: { x: 60, top: 164.5, maxWidth: 70, maxFontSize: 9, minFontSize: 6, page: 0 },
  age: { x: 345, top: 164.5, maxWidth: 45, maxFontSize: 9, minFontSize: 6, page: 0 },
  // The "Service Availed:" label starts at x=252, so region may run to ~x=248.
  region: { x: 114, top: 183.7, maxWidth: 130, maxFontSize: 9, minFontSize: 6, page: 0 },
  service: { x: 314, top: 183.7, maxWidth: 258, maxFontSize: 8, minFontSize: 6, page: 0 },
  comments: {
    // Two ruled lines, 21.7pt apart: first baseline just above y=793.2
    // (= top + size = 782.4 + 10), second just above y=814.9.
    x: 36,
    top: 782.4,
    maxWidth: 538,
    maxHeight: 44,
    maxFontSize: 10,
    minFontSize: 6,
    multiline: true,
    lineHeightRatio: 2.17,
    page: 0,
  },
  clientName: { x: 129, top: 830.9, maxWidth: 140, maxFontSize: 9, minFontSize: 6, page: 0 },
  contactNo: { x: 393, top: 830.9, maxWidth: 104, maxFontSize: 9, minFontSize: 6, page: 0 },
  email: { x: 129, top: 848.1, maxWidth: 308, maxFontSize: 9, minFontSize: 6, page: 0 },
};

/**
 * Office name — centered under the printed header (center x≈299.1), in smaller
 * italic text; same layout rules as OFFICE_NAME_FIELD_TAGALOG. The range is
 * symmetric around the header's center and stops at x=438.2 so a long name can
 * never run into the ARTA box (starts x=444.4, bottom 67). The gap to the next
 * printed line (top 82) is ~30pt.
 */
export const OFFICE_NAME_FIELD_ENGLISH = {
  page: 0,
  boxLeft: 160,
  boxRight: 438.2,
  top: 57,
  maxWidth: 278.2, // boxRight - boxLeft
  maxFontSize: 11,
  minSingleLineFontSize: 9,
  wrapFontSize: 9,
  minFontSize: 8,
  wrappedTop: 55,
  lineHeight: 11,
  maxLines: 2,
} as const;