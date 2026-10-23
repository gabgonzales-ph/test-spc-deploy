/**
 * Coordinate map for the CSM (Client Satisfaction Measurement) PDF template.
 *
 * Source template: Supabase Storage bucket "documents", path "forms/csm/<template file>"
 * Page size: 612 x 936 pt (confirmed from template)
 * Origin note: all coordinates below are TOP-based (distance from top of page, in points),
 * matching how they were measured off the template. Convert to pdf-lib's bottom-left
 * origin at draw time with `topToPdfY()` in csmPdfService.ts.
 *
 * These were derived directly from the template's embedded text layer / vector geometry
 * (word bounding boxes + detected table gridlines), then hand-tuned by trial-and-error
 * against real renders. If the template file is ever replaced/re-exported, re-derive
 * this map before trusting it.
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
    maxHeight: 45, // was 35 — too tight to ever show a real line gap; template has
                   // ~54.5pt between the label and the Email row, this leaves a buffer
    maxFontSize: 11,
    minFontSize: 6,
    multiline: true,
    lineHeightRatio: 2, // was tested up to 50/2.5 with no visible change — the old
                          // maxHeight forced font-shrink to compensate for any ratio
                          // increase, canceling it out. With more room, this now
                          // actually widens the gap instead of just shrinking text.
  },
};

/**
 * Office name placeholder area — the template already reserves a box here
 * ("(Insert agency logo here)" / "(Insert agency name here)"), directly above
 * the "HELP US SERVE YOU BETTER!" title. `x` is unused for this field; it's
 * drawn horizontally centered within [boxLeft, boxRight] by csmPdfService.ts.
 */
export const OFFICE_NAME_FIELD = {
  boxLeft: 195.6,
  boxRight: 419.6,
  top: 42, // vertically centered within the box (38.7–76.7)
  maxWidth: 524, // boxRight - boxLeft
  maxFontSize: 22,
  minFontSize: 22,
} as const;

/* ============================================================================
 * TAGALOG TEMPLATE — 1 PAGE (csm_onepage.pdf)
 *
 * Source template: Supabase Storage bucket "documents", path
 * "forms/csm/csm_onepage.pdf". Replaces the earlier 2-page Tagalog template
 * (csmform_tagalog.pdf) — the SQD table (SQD0–SQD8) now fits on a single
 * page instead of splitting SQD6–8 onto a second page, and "Control No:"
 * now appears only once instead of being repeated per page.
 *
 * Page size: 612 x 1008pt (confirmed via pdfinfo) — same page height as the
 * old template's individual pages, just consolidated into one.
 *
 * Derived directly from the template's embedded text layer (pdfplumber word
 * boxes) and vector table gridlines (pdfplumber line/rect detection) — this
 * template is native text + vector, not a scan, so no OCR/pixel-gridline
 * detection was needed. Checkbox positions for client type / sex / CC1–3
 * are unchanged from the old page-0 map (that section of the layout did not
 * move); SQD table columns are also unchanged (same table width/columns).
 * Row y-centers, comments box, and email field are new (single-page layout).
 * NOT yet hand-tuned against a real render — flag for eyeball verification
 * once generated PDFs can be visually checked.
 *
 * Unlike the English template, this template has no reserved office-name
 * placeholder box. OFFICE_NAME_FIELD_TAGALOG below is a first-guess
 * placement (centered in the empty space between "Control No:" and the
 * title, left of the ARTA header graphic) — flagged as needing eyeball
 * tuning against a real render before trusting it.
 *
 * `page` fields are kept (always 0) per team decision, to preserve the
 * paged data shape / paged rendering logic in csmPdfService.ts for
 * future-proofing, even though this template is single-page.
 *
 * Origin note: same convention as before — all coordinates are TOP-based
 * (distance from top of page, in points).
 * ==========================================================================*/

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

/** Checkbox center points, keyed by field group -> option value. All on page 0
 * (single-page template). Client type / sex / CC1–3 positions are unchanged
 * from the old 2-page map's page 0 — that part of the layout did not move. */
export const CHECKBOXES_TAGALOG = {
  clientType: {
    citizen: { x: 104.0, y: 157.9, page: 0 } as PagedPoint,
    business: { x: 172.5, y: 157.9, page: 0 } as PagedPoint,
    government: { x: 227.1, y: 157.9, page: 0 } as PagedPoint,
  },
  sex: {
    male: { x: 225.6, y: 178.5, page: 0 } as PagedPoint,
    female: { x: 268.1, y: 178.5, page: 0 } as PagedPoint,
  },
  cc1: {
    1: { x: 85.5, y: 306.5, page: 0 } as PagedPoint,
    2: { x: 85.5, y: 316.5, page: 0 } as PagedPoint,
    3: { x: 85.5, y: 326.5, page: 0 } as PagedPoint,
    4: { x: 85.5, y: 336.4, page: 0 } as PagedPoint,
  },
  cc2: {
    1: { x: 85.5, y: 384.3, page: 0 } as PagedPoint,
    2: { x: 85.5, y: 394.3, page: 0 } as PagedPoint,
    3: { x: 85.5, y: 404.2, page: 0 } as PagedPoint,
    4: { x: 256.5, y: 384.3, page: 0 } as PagedPoint,
    5: { x: 256.5, y: 394.3, page: 0 } as PagedPoint, // N/A
  },
  cc3: {
    1: { x: 85.5, y: 442.9, page: 0 } as PagedPoint,
    2: { x: 85.5, y: 452.9, page: 0 } as PagedPoint,
    3: { x: 255.6, y: 442.9, page: 0 } as PagedPoint,
    4: { x: 256.0, y: 452.9, page: 0 } as PagedPoint, // N/A
  },
} as const;

/** SQD table: 6 answer columns (center-x), in points. Derived from the
 * template's vertical gridlines (x = 36.5, 252.5, 303.5, 355.5, 411.5,
 * 463.5, 510.5, 558.5) — unchanged from the old map, same table width. */
export const SQD_COLUMN_X_TAGALOG = {
  "Strongly Disagree": 278,
  Disagree: 329.5,
  "Neither Agree nor Disagree": 383.5,
  Agree: 437.5,
  "Strongly Agree": 487,
  "Not Applicable": 534.5,
} as const;

/** SQD row centers (center-y), all on page 0 — the table's 9 rows (plus
 * header) now all fit on the single page. Derived from horizontal
 * gridlines at top = 494.5, 586.5, 613.5, 641.5, 677.5, 704.5, 740.5,
 * 776.5, 803.5, 839.5, 875.5 (header band: 494.5–586.5, then one band per
 * SQD row). `page` kept at 0 for shape-compatibility with paged helpers. */
export const SQD_ROW_Y_TAGALOG: Record<
  "sqd0" | "sqd1" | "sqd2" | "sqd3" | "sqd4" | "sqd5" | "sqd6" | "sqd7" | "sqd8",
  { y: number; page: number }
> = {
  sqd0: { y: 600.0, page: 0 },
  sqd1: { y: 627.5, page: 0 },
  sqd2: { y: 659.5, page: 0 },
  sqd3: { y: 691.0, page: 0 },
  sqd4: { y: 722.5, page: 0 },
  sqd5: { y: 758.5, page: 0 },
  sqd6: { y: 790.0, page: 0 },
  sqd7: { y: 821.5, page: 0 },
  sqd8: { y: 857.5, page: 0 },
};

/** Free-text field placements. controlNo now appears only once (the
 * single-page template has a single "Control No:" label), but is kept as
 * an array of one spec for shape-compatibility with the old multi-page
 * calling code in csmPdfService.ts (`.forEach()` over the array still works
 * unchanged). Everything else appears once, all on page 0. */
/**
 * IMPORTANT — `top` semantics differ between single-line and multiline specs
 * here:
 *  - Single-line specs (controlNo, date, age, region, service, email): `top`
 *    is the field's BASELINE, i.e. the bottom edge of the template's ruled
 *    underline/blank for that field (taken directly from each value's
 *    `bottom` in the pdfplumber word extraction). drawSingleLineField()
 *    draws directly at this y with no size-dependent offset, so the text
 *    sits on its line consistently whether it renders at maxFontSize or has
 *    shrunk to fit (e.g. a long region name).
 *  - The multiline spec (comments): `top` is still a box TOP (first line's
 *    starting position), since drawMultiLineField wraps downward from it —
 *    unchanged from the original design.
 */
export const TEXT_FIELDS_TAGALOG: Record<string, PagedTextFieldSpec | PagedTextFieldSpec[]> = {
  controlNo: [{ x: 90, top: 24, maxWidth: 60, maxFontSize: 10, minFontSize: 6, page: 0 }],
  date: { x: 64, top: 181.7, maxWidth: 55, maxFontSize: 10, minFontSize: 6, page: 0 },
  age: { x: 396, top: 181.7, maxWidth: 55, maxFontSize: 10, minFontSize: 6, page: 0 },
  region: { x: 74, top: 200.5, maxWidth: 95, maxFontSize: 10, minFontSize: 6, page: 0 },
  service: { x: 302.6, top: 200.5, maxWidth: 200, maxFontSize: 8, minFontSize: 6, page: 0 },
  email: { x: 142.5, top: 950.4, maxWidth: 170, maxFontSize: 9, minFontSize: 6, page: 0 },
  comments: {
    // Two explicit ruled blank lines (not one open box like the English
    // template): line 1 at top=906.7–915.7, line 2 at top=925.0–934.0,
    // both spanning x=36 to 476.5. `top` set to the first line's top edge
    // so drawMultiLineField's first line lands on/just above line 1;
    // maxHeight covers both lines plus a small buffer. May need retuning
    // once rendered for real.
    x: 36,
    top: 905,
    maxWidth: 440,
    maxHeight: 35,
    maxFontSize: 9,
    minFontSize: 6,
    multiline: true,
    lineHeightRatio: 2.2,
    page: 0,
  },
};

/**
 * Office name placement — UNLIKE the English template, this Tagalog
 * template has no reserved placeholder box for it. This is a first-guess
 * position: centered in the empty space on page 0 between the "Control No:"
 * line (top=17–27) and the title (top=79.5), to the left of the ARTA header
 * graphic (an image at x0=459–598.5, top=14.4–66.9 — confirmed via
 * pdfplumber's image list, since this box is a picture, not text/vector).
 * NEEDS EYEBALL TUNING against a real render — not yet trial-and-error
 * verified the way the English OFFICE_NAME_FIELD was.
 */
export const OFFICE_NAME_FIELD_TAGALOG = {
  page: 0,
  boxLeft: 120,
  boxRight: 450,
  top: 55,
  maxWidth: 330, // boxRight - boxLeft
  maxFontSize: 15,
  minFontSize: 10,
} as const;