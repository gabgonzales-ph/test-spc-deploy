/**
 * CSM PDF export test script.
 *
 * Generates one PDF per scenario into ./csm-test-output/ so every layout case
 * can be eyeballed, and runs basic sanity checks (valid PDF header, single page).
 *
 * Usage (from the project root):
 *   bun run scripts/test-csm-pdf.ts                     # download template from Supabase (needs .env)
 *   bun run scripts/test-csm-pdf.ts --local=./CSM-ONLINE-TAGALOGv2.pdf   # use a local template file, no Supabase
 *   bun run scripts/test-csm-pdf.ts --lang=en           # language to request (default: tl)
 *   bun run scripts/test-csm-pdf.ts --only=long-name    # run a single scenario by name
 *   bun run scripts/test-csm-pdf.ts --calibration       # also write a calibration PDF (Supabase mode only)
 *
 * Exit code is 1 if any scenario fails.
 */
import { PDFDocument } from "pdf-lib";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import {
  fillCsmPdf,
  generateCalibrationPdf,
  generateCsmPdf,
  resolvePdfLang,
  type CsmResponseForPdf,
} from "@/backend/utils/csm/csmPdfService";

// ---------------------------------------------------------------------
// CLI args
// ---------------------------------------------------------------------
const args = process.argv.slice(2);
const getArg = (name: string): string | undefined =>
  args.find((a) => a.startsWith(`--${name}=`))?.split("=").slice(1).join("=");
const hasFlag = (name: string) => args.includes(`--${name}`);

const localTemplate = getArg("local");
const lang = resolvePdfLang(getArg("lang") ?? "tl");
const only = getArg("only");
const OUT_DIR = path.resolve(process.cwd(), "csm-test-output");

// ---------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------
const BASE: CsmResponseForPdf = {
  control_no: "2026-11-09-001",
  client_type: "citizen",
  transaction_date: "2026-11-02",
  sex: "female",
  age: 34,
  region: "Region IV-A",
  service: "Issuance of Business Permit",
  cc1: 1,
  cc2: 1,
  cc3: 2,
  sqd0: "Strongly Agree",
  sqd1: "Agree",
  sqd2: "Neither Agree nor Disagree",
  sqd3: "Disagree",
  sqd4: "Strongly Disagree",
  sqd5: "Not Applicable",
  sqd6: "Agree",
  sqd7: "Strongly Agree",
  sqd8: "Agree",
  comments:
    "Maganda ang serbisyo at magalang ang mga kawani. Sana lang po ay madagdagan ang upuan sa waiting area para sa mga senior citizen.",
  email_address: "juan.delacruz@email.com",
  client_name: "Juan Dela Cruz",
  contact_no: "0917 123 4567",
  office_name: "City Treasurer's Office",
};

const SCENARIOS: { name: string; note: string; row: CsmResponseForPdf }[] = [
  { name: "typical", note: "Everything filled, short values", row: BASE },
  {
    name: "minimal",
    note: "Optional fields empty: no sex/age/comments/email/name/contact",
    row: {
      ...BASE,
      sex: null,
      age: null,
      comments: null,
      email_address: null,
      client_name: null,
      contact_no: null,
    },
  },
  {
    name: "cc1-not-aware",
    note: "CC1 = 4 -> CC2 N/A (5) and CC3 N/A (4)",
    row: { ...BASE, client_type: "government", cc1: 4, cc2: 5, cc3: 4 },
  },
  {
    name: "business-male",
    note: "Other client type / sex checkboxes",
    row: { ...BASE, client_type: "business", sex: "male", age: 129 },
  },
  {
    name: "all-sqd-columns",
    note: "SQD0-8 cycle through each column (SD, D, N, A, SA, NA)",
    row: {
      ...BASE,
      sqd0: "Strongly Disagree",
      sqd1: "Disagree",
      sqd2: "Neither Agree nor Disagree",
      sqd3: "Agree",
      sqd4: "Strongly Agree",
      sqd5: "Not Applicable",
      sqd6: "Strongly Disagree",
      sqd7: "Disagree",
      sqd8: "Neither Agree nor Disagree",
    },
  },
  {
    name: "long-office-name",
    note: "Long office name must stay centered and clear of the ARTA box",
    row: {
      ...BASE,
      office_name: "City Mayor's Office - Records and Administrative Division",
    },
  },
  {
    name: "very-long-office-name",
    note: "Office name longer than the slot -> shrinks to 8pt, then ellipsis",
    row: {
      ...BASE,
      office_name:
        "City Environmental and Natural Resources Office - Solid Waste Management and Coastal Resource Division Annex",
    },
  },
  {
    name: "long-name",
    note: "Client name > field width -> shrinks then ellipsis",
    row: {
      ...BASE,
      client_name:
        "Maria Concepcion Magdalena Dela Cruz-Santos y Villanueva III",
    },
  },
  {
    name: "contact-formats",
    note: "Contact number with + ( ) - and spaces, max 12 digits",
    row: { ...BASE, contact_no: "+63 (917) 123-4567" },
  },
  {
    name: "long-service-region",
    note: "Long service and region values",
    row: {
      ...BASE,
      region: "Region IV-A (CALABARZON)",
      service:
        "Application for Locational Clearance for Non-Commercial Developments and Subdivision Projects",
    },
  },
  {
    name: "long-comment",
    note: "Comment far longer than two ruled lines -> shrinks / ellipsis",
    row: { ...BASE, comments: "Napakahusay ng serbisyo ninyo. ".repeat(40).trim() },
  },
  {
    name: "unicode",
    note: "Characters outside WinAnsi must print as '?', not crash",
    row: {
      ...BASE,
      client_name: "Peña Ñ “quotes” 日本 😀",
      office_name: "Ñandú Office",
      comments: "Salamat po 😀 — magandang serbisyo",
    },
  },
  {
    name: "whitespace",
    note: "Newlines/tabs/multiple spaces collapse to single spaces",
    row: {
      ...BASE,
      client_name: "Juan\n\tDela   Cruz",
      comments: "Linya isa.\n\nLinya dalawa.\t\tTapos.",
    },
  },
];

// ---------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------
async function render(row: CsmResponseForPdf): Promise<Uint8Array> {
  if (localTemplate) {
    const templateBytes = readFileSync(path.resolve(localTemplate));
    const doc = await PDFDocument.load(templateBytes);
    return fillCsmPdf(doc, row, lang);
  }
  return generateCsmPdf(row, lang);
}

async function check(bytes: Uint8Array): Promise<string[]> {
  const problems: string[] = [];
  const header = Buffer.from(bytes.slice(0, 5)).toString("latin1");
  if (header !== "%PDF-") problems.push(`bad header "${header}"`);
  if (bytes.length < 10_000) problems.push(`suspiciously small (${bytes.length} bytes)`);
  try {
    const doc = await PDFDocument.load(bytes);
    if (doc.getPageCount() !== 1) problems.push(`expected 1 page, got ${doc.getPageCount()}`);
  } catch (e) {
    problems.push(`output is not loadable: ${e instanceof Error ? e.message : String(e)}`);
  }
  return problems;
}

async function main() {
  mkdirSync(OUT_DIR, { recursive: true });
  console.log(
    `CSM PDF test | lang=${lang} | template=${localTemplate ? `local:${localTemplate}` : "Supabase"} | out=${OUT_DIR}\n`
  );

  const selected = only ? SCENARIOS.filter((s) => s.name === only) : SCENARIOS;
  if (selected.length === 0) {
    console.error(`No scenario named "${only}". Available: ${SCENARIOS.map((s) => s.name).join(", ")}`);
    process.exit(1);
  }

  let failed = 0;
  for (const s of selected) {
    const file = path.join(OUT_DIR, `csm-${lang}-${s.name}.pdf`);
    try {
      const bytes = await render(s.row);
      writeFileSync(file, bytes);
      const problems = await check(bytes);
      if (problems.length) {
        failed++;
        console.log(`FAIL  ${s.name}  (${problems.join("; ")})`);
      } else {
        console.log(`ok    ${s.name}  ${(bytes.length / 1024).toFixed(0)} KB  - ${s.note}`);
      }
    } catch (e) {
      failed++;
      console.log(`FAIL  ${s.name}  threw: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  if (hasFlag("calibration")) {
    if (localTemplate) {
      console.log("\nskip  calibration (needs Supabase; run without --local)");
    } else {
      try {
        const file = path.join(OUT_DIR, `csm-${lang}-calibration.pdf`);
        writeFileSync(file, await generateCalibrationPdf(lang));
        console.log(`\nok    calibration -> ${file}`);
      } catch (e) {
        failed++;
        console.log(`\nFAIL  calibration  threw: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
  }

  console.log(
    `\n${selected.length - failed}/${selected.length} scenarios passed. Open the PDFs in ${OUT_DIR} to check placement by eye.`
  );
  process.exit(failed ? 1 : 0);
}

main();